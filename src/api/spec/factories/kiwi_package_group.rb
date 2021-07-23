FactoryBot.define do
  factory :kiwi_package_group, class: 'Kiwi::PackageGroup' do
    association :image, factory: :kiwi_image

    kiwi_type { Kiwi::PackageGroup.kiwi_types.keys[Faker::Number.between(from: 0, to: Kiwi::PackageGroup.kiwi_types.keys.length - 1)] }
    profiles { Faker::Creature::Cat.name }
    pattern_type { Faker::Creature::Cat.name }

    factory :kiwi_package_group_non_empty do
      after(:create) do |group|
        group.packages << create(:kiwi_package)
        group.packages << create(:kiwi_package)
      end
    end
  end
end
