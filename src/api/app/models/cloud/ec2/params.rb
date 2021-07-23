module Cloud
  module Ec2
    class Params
      include ActiveModel::Validations
      include ActiveModel::Model

      attr_accessor :region, :ami_name, :vpc_subnet_id

      validates :region, presence: true, inclusion: {
        in: Cloud::Ec2::Configuration::REGIONS.map(&:second), message: "'%{value}' is not a valid EC2 region"
      }
      validates :ami_name, presence: true, length: { maximum: 100 }
      validate :valid_ami_name
      validates :vpc_subnet_id, format: { with: /\Asubnet-[-\w]+\z/, message: 'not a valid format', allow_blank: true }

      def self.build(params)
        new(params.slice(:region, :ami_name, :vpc_subnet_id))
      end

      private

      def valid_ami_name
        return if Project.valid_name?(ami_name)

        errors.add(:ami_name, "'#{ami_name}' is not a valid ami name (only letters, numbers, dots and hyphens)")
      end
    end
  end
end
