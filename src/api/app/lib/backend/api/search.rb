module Backend
  module Api
    # Class that connect to endpoints related to the search
    class Search
      extend Backend::ConnectionHelper

      # Performs a search of the binary in a project list
      # @return [String]
      def self.binary(project_names, binary_name)
        project_list = project_names.map { |project_name| "@project='#{CGI.escape(project_name)}'" }.join('+or+')
        http_post("/search/published/binary/id?match=(@name='#{CGI.escape(binary_name)}'+and+(#{project_list}))")
      end

      def self.published_binaries_for_package(project_name, package_name)
        http_get('/search/published/binary/id', params: { match: "@project='#{project_name}' and @package='#{package_name}'" })
      end

      # Performs a search of packages with a link
      def self.packages_with_link(package_names)
        packages_list = package_names.map { |name| "linkinfo/@package='#{CGI.escape(name)}'" }.join('+or+')
        http_get("/search/package/id?match=(#{packages_list})")
      end

      # Performs a search of incident packages for a maintenance project
      def self.incident_packages(project_name, package_name, maintenance_project_name)
        conditions = ["linkinfo/@package=\"#{CGI.escape(package_name)}\""]
        conditions << "linkinfo/@project=\"#{CGI.escape(project_name)}\""
        conditions << "starts-with(@project,\"#{CGI.escape(maintenance_project_name)}%3A\")"
        http_post("/search/package/id?match=(#{conditions.join('+and+')})")
      end

      def self.product_ids(project_name)
        http_get('/search/package/id', params: { match: "@project='#{project_name}' and starts-with(@name,'_product:')" })
      end

      def self.packages_for_project(project_name)
        http_get('/search/package', params: { match: "@project='#{project_name}'" })
      end

      def self.projects(projects)
        xpath = projects.collect { |project| "@name='#{project}'" }.join(' or ')
        http_get('/search/project', params: { match: xpath }) if xpath.present?
      end
    end
  end
end
