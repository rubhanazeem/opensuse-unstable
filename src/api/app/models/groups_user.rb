class GroupsUser < ApplicationRecord
  include ActiveModel::Validations

  belongs_to :user
  belongs_to :group

  validates :user, presence: true
  validates :group, presence: true
  validate :validate_duplicates, on: :create
  validates_with AllowedUserValidator

  private

  def validate_duplicates
    return unless GroupsUser.find_by(user: user, group: group)

    errors.add(:user, 'User already has this group')
  end
end

# == Schema Information
#
# Table name: groups_users
#
#  id         :integer          not null, primary key
#  email      :boolean          default(TRUE)
#  created_at :datetime
#  group_id   :integer          default(0), not null, indexed => [user_id]
#  user_id    :integer          default(0), not null, indexed => [group_id], indexed
#
# Indexes
#
#  groups_users_all_index  (group_id,user_id) UNIQUE
#  user_id                 (user_id)
#
# Foreign Keys
#
#  groups_users_ibfk_1  (group_id => groups.id)
#  groups_users_ibfk_2  (user_id => users.id)
#
