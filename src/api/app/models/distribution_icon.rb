class DistributionIcon < ApplicationRecord
  validates :url, presence: true
  # TODO: Allow file-upload later on, probably thru CarrierWave gem

  has_and_belongs_to_many :distributions
end

# == Schema Information
#
# Table name: distribution_icons
#
#  id     :integer          not null, primary key
#  height :integer
#  url    :string(255)      not null
#  width  :integer
#
