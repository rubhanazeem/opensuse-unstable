require 'rails_helper'
# WARNING: If you change owner tests make sure you uncomment this line
# and start a test backend. Some of the Owner methods
# require real backend answers for projects/packages.
# CONFIG['global_write_through'] = true

RSpec.describe Webui::SearchController, vcr: true do
  let!(:user) { create(:confirmed_user, :with_home, login: 'Iggy') }
  let!(:develuser) { create(:confirmed_user, :with_home, login: 'DevelIggy') }
  let!(:package) { create(:package, name: 'TestPack', project: Project.find_by(name: 'home:Iggy')) }
  let!(:develpackage) { create(:package, name: 'DevelPack', project: Project.find_by(name: 'home:DevelIggy')) }
  let(:owner_attrib) { create(:attrib, attrib_type: AttribType.where(name: 'OwnerRootProject').first, project: Project.find_by(name: 'home:Iggy')) }

  before do
    login user
    owner_attrib
  end

  describe 'GET #owner' do
    it 'just returns with blank search text' do
      get :owner, params: { search_text: '', owner: 1 }
      expect(response).to have_http_status(:success)
    end

    it 'warns about short search text' do
      get :owner, params: { search_text: 'a', owner: 1 }
      expect(controller).to set_flash[:error].to('Search string must contain at least two characters.')
    end

    it 'assigns results' do
      collection = file_fixture('owner_search_collection.xml').read
      stub_request(:post, "#{CONFIG['source_url']}/search/published/binary/id?match=(@name='package'%20and%20(@project='home:Iggy'))").and_return(body: collection)
      get :owner, params: { search_text: 'package', owner: 1 }
      expect(assigns(:results)[0].users).to eq('maintainer' => [user])
    end
  end

  describe 'GET #search' do
    it 'just returns without search text' do
      get :index
      expect(response).to have_http_status(:success)
    end

    context 'with a short search text' do
      before do
        get :index, params: { search_text: 'a' }
      end

      it { expect(flash[:error]).to eq('Search string must contain at least two characters.') }
      it { expect(response).to have_http_status(:success) }
    end

    context 'request number when string starts with a #' do
      before do
        get :index, params: { search_text: '#1' }
      end

      it { is_expected.to redirect_to(controller: :request, action: :show, number: 1) }
    end

    context 'with search_text starting with obs://' do
      context 'and a package' do
        before do
          allow(Package).to receive(:exists_by_project_and_name).and_return(true)
          get :index, params: { search_text: "obs://build.opensuse.org/#{user.home_project.name}/i586/1-#{package.name}" }
        end

        it { is_expected.to redirect_to(controller: :package, action: :show, project: user.home_project, package: package.name, rev: 1) }
      end

      context 'and a non existent package' do
        before do
          request.env['HTTP_REFERER'] = root_url # Needed for the redirect_to :back
          get :index, params: { search_text: "obs://build.opensuse.org/#{user.home_project.name}/i586/1-non_existent_package" }
        end

        it { expect(flash[:notice]).to eq('Sorry, this disturl does not compute...') }
        it { is_expected.to redirect_to(root_url) }
      end

      context 'with improper disturl' do
        before do
          # https://github.com/openSUSE/open-build-service/issues/5510
          get :index, params: { search_text: 'obs://openSUSE:Leap:15.0:Update', name: 1, project: 1, package: 1 }
        end

        it { expect(flash[:notice]).to eq('Sorry, this disturl does not compute...') }
      end
    end

    context 'with proper parameters but no results' do
      before do
        allow(ThinkingSphinx).to receive(:search).and_return([])
        get :index, params: { search_text: 'whatever', project: 1, package: 1, name: 1 }
      end

      it { expect(flash[:notice]).to eq('Your search did not return any results.') }
      it { expect(response).to have_http_status(:success) }
      it { expect(assigns(:results)).to be_empty }
    end

    context 'with proper parameters and some results' do
      before do
        allow(ThinkingSphinx).to receive(:search).and_return(["Fake result with #{package.name}"])
        get :index, params: { search_text: package.name, project: 1, package: 1, name: 1 }
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(assigns(:results)).not_to be_empty }
    end
  end
end
