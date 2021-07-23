module MultibuildPackage
  extend ActiveSupport::Concern

  class_methods do
    def valid_multibuild_name?(name)
      valid_name?(name, true)
    end

    def striping_multibuild_suffix(name)
      # exception for package names used to have a collon
      return name if name.start_with?('_patchinfo:', '_product:')

      name.gsub(/:.*$/, '')
    end
  end

  def multibuild?
    file_exists?('_multibuild')
  end

  def multibuild_flavor?(name)
    return false unless multibuild?

    # Support passing both with and without prefix.
    # Like package:flavor or just flavor
    name = name.split(':', 2).last
    multibuild_flavors.include?(name)
  end

  def multibuild_flavors
    return [] unless multibuild?

    flavors = Xmlhash.parse(source_file('_multibuild'))['flavor']
    return [flavors] if flavors.is_a?(String)

    flavors
  end
end
