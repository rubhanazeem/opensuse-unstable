module Kiwi
  class Image
    class XmlBuilder
      def initialize(image)
        @image = image
      end

      def build
        doc = Nokogiri::XML::DocumentFragment.parse(@image.kiwi_body)
        image = doc.at_css('image')

        return nil unless image && image.first_element_child

        doc = update_packages(doc)
        doc = update_repositories(doc)
        doc = update_description(doc)
        doc = update_preferences(doc)
        doc = update_profiles(doc)

        Nokogiri::XML(doc.to_xml, &:noblanks).to_xml(indent: kiwi_indentation(doc))
      end

      private

      # Creates or updates the containerconfig name and tag inside the <preferences>.
      # It leaves the other attributes untouched. For example:
      #   <preferences>
      #     <type image="docker" boot="grub">
      #       <containerconfig name="my_container" tag="latest"/>
      #       <oemconfig>test</oemconfig>
      #     </type>
      #     <packagemanager>zypper</packagemanager>
      #   </preferences>
      def update_preferences(document)
        return document if @image.preferences.blank?

        @image.preferences.each.with_index(1) do |preference, index|
          document = update_preference_version(document, preference, index)
          document = update_preference_type_containerconfig(document, preference, index)
        end

        document
      end

      def update_preference_version(document, preference, index)
        return document if preference.version.blank?

        if document.xpath("image/preferences[#{index}]/version").any?
          document.xpath("image/preferences[#{index}]/version").first.content = preference.version
          return document
        end

        document.xpath("image/preferences[#{index}]").first.add_child("<version>#{preference.version}</version>") if document.xpath("image/preferences[#{index}]").any?

        document
      end

      def update_preference_type_containerconfig(document, preference, index)
        if document.xpath("image/preferences[#{index}]/type/containerconfig").any?
          document.xpath("image/preferences[#{index}]/type/containerconfig").first['name'] = preference.type_containerconfig_name
          document.xpath("image/preferences[#{index}]/type/containerconfig").first['tag'] = preference.type_containerconfig_tag
        elsif preference.type_containerconfig_tag.present? || preference.type_containerconfig_name.present?
          document.xpath("image/preferences[#{index}]/type").first.add_child(preference.containerconfig_xml)
        end

        document
      end

      def update_description(document)
        return document if @image.description.blank?

        if document.xpath('image/description[@type="system"]').first
          ['author', 'contact', 'specification'].each do |element_name|
            description_xml_element = find_or_create_description_xml_element(document, element_name)
            document.xpath('image/description[@type="system"]').first.add_child(description_xml_element)
          end
        else
          document.at_css('image').first_element_child.before(@image.description.to_xml)
        end
        document
      end

      def find_or_create_description_xml_element(document, element_name)
        element_xml = document.xpath("image/description[@type='system']/#{element_name}").first
        element_xml ||= Nokogiri::XML::Node.new(element_name, document)
        element_xml.content = @image.description.send(element_name)
        element_xml
      end

      def update_packages(document)
        # for now we only write the default package group
        xml_packages = @image.default_package_group.to_xml
        packages = document.xpath('image/packages[@type="image"]').first
        if packages
          packages.replace(xml_packages)
        else
          document.at_css('image').last_element_child.after(xml_packages)
        end
        document
      end

      def update_repositories(document)
        repository_position = document.xpath('image/repository').first.try(:previous) || document.at_css('image').last_element_child
        document.xpath('image/repository').remove
        xml_repos = repositories_for_xml.map(&:to_xml).join("\n")
        repository_position.after(xml_repos)
        document
      end

      def update_profiles(document)
        comment = document.xpath('comment()[contains(., "OBS-Profiles:")]')

        document.xpath('comment()[contains(., "OBS-Profiles:")]').remove unless comment.empty?

        selected_profiles = @image.profiles.selected.pluck(:name)
        document.xpath('image').before(Nokogiri::XML::Comment.new(document, " OBS-Profiles: #{selected_profiles.join(' ')} ")) unless selected_profiles.empty?

        document
      end

      def repositories_for_xml
        if @image.use_project_repositories?
          [Kiwi::Repository.new(source_path: 'obsrepositories:/', repo_type: 'rpm-md')]
        else
          @image.repositories
        end
      end

      def kiwi_indentation(xml)
        content = xml.xpath('image').children.first.try(:content)
        content ? content.delete("\n").length : 2
      end
    end
  end
end
