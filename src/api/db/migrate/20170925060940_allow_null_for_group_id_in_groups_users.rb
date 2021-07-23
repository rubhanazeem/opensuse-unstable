class AllowNullForGroupIdInGroupsUsers < ActiveRecord::Migration[5.1]
  def up
    change_column :groups_users, :group_id, :integer, null: true, default: 0, before: :user_id
  end

  def down
    change_column :groups_users, :group_id, :integer, null: false, default: 0, before: :user_id
  end
end
