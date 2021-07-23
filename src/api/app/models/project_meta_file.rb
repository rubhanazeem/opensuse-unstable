class ProjectMetaFile < ProjectFile
  def initialize(attributes = {})
    super
    @name = '_meta'
  end

  # calculates the real url on the backend to search the file
  def full_path(query = {})
    URI.encode("/source/#{project_name}/#{name}") + "?#{query.to_query}"
  end

  # You dont want to change name of _meta
  private :name=
end
