module Kiwi
  class Package < ApplicationRecord
    belongs_to :package_group
    has_one :kiwi_image, through: :package_groups

    validates :name, presence: { message: 'can\'t be blank' }

    def to_h
      hash = { name: name }
      hash[:arch] = arch if arch.present?
      hash[:replaces] = replaces if replaces.present?
      hash[:bootinclude] = bootinclude if bootinclude.present?
      hash[:bootdelete] = bootdelete if bootdelete.present?
      hash
    end
  end
end

# == Schema Information
#
# Table name: kiwi_packages
#
#  id               :integer          not null, primary key
#  arch             :string(255)
#  bootdelete       :boolean
#  bootinclude      :boolean
#  name             :string(255)      not null
#  replaces         :string(255)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  package_group_id :integer          indexed
#
# Indexes
#
#  index_kiwi_packages_on_package_group_id  (package_group_id)
#
# Foreign Keys
#
#  fk_rails_...  (package_group_id => kiwi_package_groups.id)
#
