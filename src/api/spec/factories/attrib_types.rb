FactoryBot.define do
  factory :attrib_type do
    sequence(:name) { |n| "attribute_factory_#{n}" }
    attrib_namespace

    factory :attrib_type_with_default_value do
      after(:create) do |attrib_type, _evaluator|
        create(:attrib_default_value, attrib_type: attrib_type)
      end
    end

    factory :obs_attrib_type do
      attrib_namespace { AttribNamespace.find_or_create_by(name: 'OBS') }
    end
  end
end
