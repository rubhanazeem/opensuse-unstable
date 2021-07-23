require 'rails_helper'

RSpec.describe Webui::Users::RssTokensController do
  describe 'POST #create' do
    let(:user) { create(:confirmed_user) }

    it_behaves_like 'require logged in user' do
      let(:method) { :post }
      let(:action) { :create }
    end

    context 'with a user with an existent token' do
      let!(:last_token) { user.create_rss_token.string }

      before do
        login(user)
        post :create
      end

      it { expect(flash[:success]).to eq('Successfully re-generated your RSS feed url') }
      it { is_expected.to redirect_to(my_subscriptions_path) }
      it { expect(user.reload.rss_token.string).not_to eq(last_token) }
    end

    context 'with a user without a token' do
      let!(:last_token) { user.rss_token }

      before do
        login(user)
        post :create
      end

      it { expect(flash[:success]).to eq('Successfully generated your RSS feed url') }
      it { is_expected.to redirect_to(my_subscriptions_path) }
      it { expect(user.reload.rss_token).not_to be_nil }
      it { expect(last_token).to be_nil }
    end
  end
end
