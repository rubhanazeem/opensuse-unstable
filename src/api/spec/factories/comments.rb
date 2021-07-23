FactoryBot.define do
  factory :comment do
    body { Faker::Lorem.paragraph }
    user

    factory :comment_package do
      commentable { create(:package) }
    end

    factory :comment_project do
      commentable { create(:project) }
    end

    factory :comment_request do
      commentable { create(:set_bugowner_request) }
    end
  end
end
