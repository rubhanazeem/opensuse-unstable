class BinaryRelease < ApplicationRecord
  #### Includes and extends
  #### Constants
  #### Self config
  class SaveError < APIError; end

  #### Attributes
  #### Associations macros (Belongs to, Has one, Has many)
  belongs_to :repository
  belongs_to :release_package, class_name: 'Package' # optional
  belongs_to :on_medium, class_name: 'BinaryRelease'

  #### Callbacks macros: before_save, after_save, etc.
  before_create :set_release_time

  #### Scopes (first the default_scope macro if is used)

  #### Validations macros
  #### Class methods using self. (public and then private)
  def self.update_binary_releases(repository, key, time = Time.now)
    begin
      notification_payload = ActiveSupport::JSON.decode(Backend::Api::Server.notification_payload(key))
    rescue Backend::NotFoundError
      logger.error("Payload got removed for #{key}")
      return
    end
    update_binary_releases_via_json(repository, notification_payload, time)
    # drop it
    Backend::Api::Server.delete_notification_payload(key)
  end

  def self.update_binary_releases_via_json(repository, json, time = Time.now)
    oldlist = where(repository: repository, obsolete_time: nil, modify_time: nil)
    # we can not just remove it from relation, delete would affect the object.
    processed_item = {}

    # when we have a medium providing further entries
    medium_hash = {}

    BinaryRelease.transaction do
      json.each do |binary|
        # identifier
        hash = { binary_name: binary['name'],
                 binary_version: binary['version'] || 0, # docker containers have no version
                 binary_release: binary['release'] || 0,
                 binary_epoch: binary['epoch'],
                 binary_arch: binary['binaryarch'],
                 medium: binary['medium'],
                 on_medium: medium_hash[binary['medium']],
                 obsolete_time: nil,
                 modify_time: nil }
        # check for existing entry
        matching_binaries = oldlist.where(hash)
        if matching_binaries.count > 1
          Rails.logger.info "ERROR: multiple matches, cleaning up: #{matching_binaries.inspect}"
          # double definition means broken DB entries
          matching_binaries.offset(1).destroy_all
        end

        # compare with existing entry
        entry = matching_binaries.first

        if entry
          if entry.identical_to?(binary)
            # same binary, don't touch
            processed_item[entry.id] = true
            # but collect the media
            medium_hash[binary['ismedium']] = entry if binary['ismedium'].present?
            next
          end
          # same binary name and location, but updated content or meta data
          entry.modify_time = time
          entry.save!
          processed_item[entry.id] = true
          hash[:operation] = 'modified' # new entry will get "modified" instead of "added"
        end

        # complete hash for new entry
        hash[:binary_releasetime] = time
        hash[:binary_id] = binary['binaryid'] if binary['binaryid'].present?
        hash[:binary_buildtime] = nil
        hash[:binary_buildtime] = Time.strptime(binary['buildtime'].to_s, '%s') if binary['buildtime'].present?
        hash[:binary_disturl] = binary['disturl']
        hash[:binary_supportstatus] = binary['supportstatus']
        hash[:binary_cpeid] = binary['cpeid']
        if binary['updateinfoid']
          hash[:binary_updateinfo] = binary['updateinfoid']
          hash[:binary_updateinfo_version] = binary['updateinfoversion']
        end
        source_package = Package.striping_multibuild_suffix(binary['package'])
        rp = Package.find_by_project_and_name(binary['project'], source_package)
        if source_package.include?(':') && !source_package.start_with?('_product:')
          flavor_name = binary['package'].gsub(/^#{source_package}:/, '')
          hash[:flavor] = flavor_name
        end
        hash[:release_package_id] = rp.id if binary['project'] && rp
        if binary['patchinforef']
          begin
            patchinfo = Patchinfo.new(data: Backend::Api::Sources::Project.patchinfo(binary['patchinforef']))
          rescue Backend::NotFoundError
            # patchinfo disappeared meanwhile
          end
          hash[:binary_maintainer] = patchinfo.hashed['packager'] if patchinfo && patchinfo.hashed['packager']
        end

        # put a reference to the medium aka container
        hash[:on_medium] = medium_hash[binary['medium']] if binary['medium'].present?

        # new entry, also for modified binaries.
        entry = repository.binary_releases.create(hash)
        processed_item[entry.id] = true

        # store in medium case
        medium_hash[binary['ismedium']] = entry if binary['ismedium'].present?
      end

      # and mark all not processed binaries as removed
      oldlist.each do |e|
        next if processed_item[e.id]

        e.obsolete_time = time
        e.save!
        # create an additional "removed" entry here? No one asked for it yet ....
      end
    end
  end

  #### To define class methods as private use private_class_method
  #### private
  #### Instance methods (public and then protected/private)
  def set_release_time!
    self.binary_releasetime = Time.now
  end

  # esp. for docker/appliance/python-venv-rpms and friends
  def medium_container
    on_medium.try(:release_package)
  end

  def render_xml
    builder = Nokogiri::XML::Builder.new
    builder.binary(render_attributes) do |binary|
      binary.operation(operation)

      node = {}
      if release_package
        node[:project] = release_package.project.name if release_package.project != repository.project
        node[:package] = release_package.name
      end
      node[:time] = binary_releasetime if binary_releasetime
      node[:flavor] = flavor if flavor
      binary.publish(node) unless node.empty?

      build_node = {}
      build_node[:time] = binary_buildtime if binary_buildtime
      build_node[:binaryid] = binary_id if binary_id
      binary.build(build_node) if build_node.count.positive?
      binary.modify(time: modify_time) if modify_time
      binary.obsolete(time: obsolete_time) if obsolete_time

      binary.binaryid(binary_id) if binary_id
      binary.supportstatus(binary_supportstatus) if binary_supportstatus
      binary.cpeid(binary_cpeid) if binary_cpeid
      binary.updateinfo(id: binary_updateinfo, version: binary_updateinfo_version) if binary_updateinfo
      binary.maintainer(binary_maintainer) if binary_maintainer
      binary.disturl(binary_disturl) if binary_disturl

      update_for_product.each do |up|
        binary.updatefor(up.extend_id_hash(project: up.package.project.name, product: up.name))
      end

      if medium && (medium_package = on_medium.try(:release_package))
        binary.medium(project: medium_package.project.name,
                      package: medium_package.name)
      end

      binary.product(product_medium.product.extend_id_hash(name: product_medium.product.name)) if product_medium
    end
    builder.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION |
                              Nokogiri::XML::Node::SaveOptions::FORMAT)
  end

  def to_axml_id
    builder = Nokogiri::XML::Builder.new
    builder.binary(render_attributes)
    builder.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION |
                              Nokogiri::XML::Node::SaveOptions::FORMAT)
  end

  def to_axml(_opts = {})
    Rails.cache.fetch("xml_binary_release_#{cache_key_with_version}") { render_xml }
  end

  def identical_to?(binary_hash)
    # handle nil/NULL case
    buildtime = binary_hash['buildtime'].blank? ? nil : Time.strptime(binary_hash['buildtime'].to_s, '%s')

    # We ignore not set binary_id in db because it got introduced later
    # we must not touch the modification time in that case
    binary_disturl == binary_hash['disturl'] &&
      binary_supportstatus == binary_hash['supportstatus'] &&
      (binary_id.nil? || binary_id == binary_hash['binaryid']) &&
      binary_buildtime == buildtime
  end

  private

  def product_medium
    repository.product_medium.find_by(name: medium)
  end

  # renders all values, which are used as identifier of a binary entry.
  def render_attributes
    attributes = { project: repository.project.name, repository: repository.name }
    [:binary_name, :binary_epoch, :binary_version, :binary_release, :binary_arch, :medium].each do |key|
      value = send(key)
      next unless value

      ekey = key.to_s.gsub(/^binary_/, '')
      attributes[ekey] = value
    end
    attributes
  end

  def set_release_time
    # created_at, but readable in database
    self.binary_releasetime ||= Time.now
  end

  def update_for_product
    repository.product_update_repositories.map(&:product).uniq
  end

  #### Alias of methods
end

# == Schema Information
#
# Table name: binary_releases
#
#  id                        :integer          not null, primary key
#  binary_arch               :string(64)       not null, indexed => [binary_name, binary_epoch, binary_version, binary_release], indexed => [binary_name]
#  binary_buildtime          :datetime
#  binary_cpeid              :string(255)
#  binary_disturl            :string(255)
#  binary_epoch              :string(64)       indexed => [binary_name, binary_version, binary_release, binary_arch]
#  binary_maintainer         :string(255)
#  binary_name               :string(255)      not null, indexed => [binary_epoch, binary_version, binary_release, binary_arch], indexed => [binary_arch], indexed => [repository_id]
#  binary_release            :string(64)       not null, indexed => [binary_name, binary_epoch, binary_version, binary_arch]
#  binary_releasetime        :datetime         not null
#  binary_supportstatus      :string(255)
#  binary_updateinfo         :string(255)      indexed
#  binary_updateinfo_version :string(255)
#  binary_version            :string(64)       not null, indexed => [binary_name, binary_epoch, binary_release, binary_arch]
#  flavor                    :string(255)
#  medium                    :string(255)      indexed
#  modify_time               :datetime
#  obsolete_time             :datetime
#  operation                 :string(8)        default("added")
#  binary_id                 :string(255)      indexed
#  on_medium_id              :integer
#  release_package_id        :integer          indexed
#  repository_id             :integer          not null, indexed => [binary_name]
#
# Indexes
#
#  exact_search_index                                    (binary_name,binary_epoch,binary_version,binary_release,binary_arch)
#  index_binary_releases_on_binary_id                    (binary_id)
#  index_binary_releases_on_binary_name_and_binary_arch  (binary_name,binary_arch)
#  index_binary_releases_on_binary_updateinfo            (binary_updateinfo)
#  index_binary_releases_on_medium                       (medium)
#  ra_name_index                                         (repository_id,binary_name)
#  release_package_id                                    (release_package_id)
#
# Foreign Keys
#
#  binary_releases_ibfk_1  (repository_id => repositories.id)
#  binary_releases_ibfk_2  (release_package_id => packages.id)
#
