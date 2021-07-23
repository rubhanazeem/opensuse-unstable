class MaintainedProject < ApplicationRecord
  belongs_to :project
  belongs_to :maintenance_project, class_name: 'Project'

  validates :project_id, uniqueness: {
    scope: :maintenance_project_id,
    message: lambda do |object, _data|
      "is already maintained by the maintenance project ##{object.maintenance_project_id}"
    end
  }
end

# == Schema Information
#
# Table name: maintained_projects
#
#  id                     :integer          not null, primary key
#  maintenance_project_id :integer          not null, indexed, indexed => [project_id]
#  project_id             :integer          not null, indexed => [maintenance_project_id]
#
# Indexes
#
#  maintenance_project_id  (maintenance_project_id)
#  uniq_index              (project_id,maintenance_project_id) UNIQUE
#
# Foreign Keys
#
#  maintained_projects_ibfk_1  (project_id => projects.id)
#  maintained_projects_ibfk_2  (maintenance_project_id => projects.id)
#
