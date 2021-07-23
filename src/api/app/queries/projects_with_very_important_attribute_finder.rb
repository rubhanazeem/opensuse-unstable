class ProjectsWithVeryImportantAttributeFinder < AttribFinder
  def initialize(relation = Project.default_scoped, namespace = 'OBS', name = 'VeryImportantProject')
    super(relation, namespace, name)
  end
end
