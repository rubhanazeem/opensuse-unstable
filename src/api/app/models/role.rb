require 'api_error'

# The Role class represents a role in the database. Roles can have permissions
# associated with themselves. Roles can assigned be to roles and groups.
#
# The Role ActiveRecord class mixes in the "ActiveRbacMixins::RoleMixins::*" modules.
# These modules contain the actual implementation. It is kept there so
# you can easily provide your own model files without having to all lines
# from the engine's directory
class Role < ApplicationRecord
  class NotFound < APIError
    setup 404
  end

  validates :title,
            format: { with: /\A\w*\z/,
                      message: 'must not contain invalid characters' }
  validates :title,
            length: { in: 2..100,
                      too_long: 'must have less than 100 characters',
                      too_short: 'must have more than two characters',
                      allow_nil: false }

  # We want to validate a role's title pretty thoroughly.
  validates :title, uniqueness: { case_sensitive: true,
                                  message: 'is the name of an already existing role' }

  belongs_to :groups_roles
  belongs_to :attrib_type_modifiable_bies
  belongs_to :relationships
  belongs_to :roles_static_permissions
  belongs_to :roles_users

  # roles have n:m relations for users
  has_and_belongs_to_many :users, -> { distinct }
  # roles have n:m relations to groups
  has_and_belongs_to_many :groups, -> { distinct }
  # roles have n:m relations to permissions
  has_and_belongs_to_many :static_permissions, -> { distinct }

  scope :global, -> { where(global: true) }

  after_destroy :delete_hashed_cache
  after_save :delete_hashed_cache

  # Fetches all roles and stores them as a hash. Uses title attribute as hash key.
  #
  # {"Admin" => #<Role id:1>, "downloader" => #<Role id:2>, ... }
  def self.hashed
    Rails.cache.fetch('hashed_roles') do
      Role.all.index_by(&:title)
    end
  end

  def delete_hashed_cache
    Rails.cache.delete('hashed_roles')
  end

  def self.find_by_title!(title)
    find_by_title(title) || raise(NotFound, "Couldn't find Role '#{title}'")
  end

  def self.local_roles
    ['maintainer', 'bugowner', 'reviewer', 'downloader', 'reader'].map { |r| Role.hashed[r] }
  end

  def self.global_roles
    ['Admin']
  end

  def self.ids_with_permission(perm_string)
    RolesStaticPermission.joins(:static_permission)
                         .where(static_permissions: { title: perm_string })
                         .select('role_id').pluck(:role_id)
  end

  def to_s
    title
  end
  alias to_param to_s
end

# == Schema Information
#
# Table name: roles
#
#  id         :integer          not null, primary key
#  global     :boolean          default(FALSE)
#  title      :string(100)      default(""), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  parent_id  :integer          indexed
#
# Indexes
#
#  roles_parent_id_index  (parent_id)
#
# Foreign Keys
#
#  roles_ibfk_1  (parent_id => roles.id)
#
