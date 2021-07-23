require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Webui::Projects::PublicKeyController, type: :controller do
  describe 'GET #show' do
    let(:project) { create(:project, name: 'test_project', title: 'Test Project') }

    before do
      Rails.cache.clear
      # NOTE: we're not using VCR here because the backend does not have the obs signer setup by default
      keyinfo_url = "#{CONFIG['source_url']}/source/#{CGI.escape(project.name)}/_keyinfo?donotcreatecert=1&withsslcert=1"
      stub_request(:get, keyinfo_url).and_return(body: keyinfo_response)

      get :show, params: { project_name: project.name }
    end

    context 'with a project that has a public key' do
      let(:gpg_public_key) { Faker::Lorem.characters(number: 1024) }
      let(:keyinfo_response) do
        <<-XML
          <keyinfo project="Test">
            <pubkey keyid="0292741d" algo="rsa" keysize="2048" expires="1554571193" fingerprint="f9fe d209 ff53 6d54 ec96 916a 45d4 5b02 0292 741d">
              #{gpg_public_key}
            </pubkey>
          </keyinfo>
        XML
      end

      it { expect(response.header['Content-Disposition']).to include('attachment') }
      it { expect(response.body.strip).to eq(gpg_public_key) }
    end

    context 'with a project that has no public key' do
      let(:keyinfo_response) { '<keyinfo />' }

      it { is_expected.to redirect_to(project_show_path(project)) }
      it { expect(flash[:error]).not_to be_empty }
    end
  end
end
