require 'rails_helper'

RSpec.describe Token::RebuildPolicy do
  subject { described_class }

  describe '#create' do
    context 'user inactive' do
      let(:user_token) { create(:rebuild_token, user: user) }

      include_examples 'non-active users cannot use a token'
    end

    context 'user active' do
      let(:user_token) { create(:rebuild_token, user: user, package: package) }
      let(:other_user_token) { create(:rebuild_token, user: other_user) }

      include_examples 'active users token basic tests'
    end
  end
end
