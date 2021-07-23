class CreateEc2Configuration < ActiveRecord::Migration[5.1]
  def change
    create_table :cloud_ec2_configurations, id: :integer do |t|
      t.belongs_to :user, index: true, type: :integer
      t.string :external_id, charset: 'utf8'
      t.string :arn, charset: 'utf8'

      t.timestamps
    end
    add_index :cloud_ec2_configurations, [:external_id, :arn], unique: true
  end
end
