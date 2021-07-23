require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Webui::Cloud::UploadJob::LogsController, type: :controller, vcr: true do
  let!(:user) { create(:confirmed_user, login: 'adrian') }
  let(:project) { create(:project, name: 'Apache') }
  let!(:package) { create(:package, name: 'apache2', project: project) }

  describe '#show' do
    context 'without an EC2 configuration' do
      before do
        login(user)
        get :show, params: { upload_id: 42 }
      end

      it { expect(response).to redirect_to(cloud_ec2_configuration_path) }
    end

    context 'with an EC2 configuration' do
      let(:ec2_configuration) { create(:ec2_configuration) }
      let(:user_with_ec2_configuration) { create(:confirmed_user, login: 'tom', ec2_configuration: ec2_configuration) }

      before do
        login(user_with_ec2_configuration)
      end

      context 'and an upload job' do
        let(:upload_job) { create(:upload_job, user: user_with_ec2_configuration) }
        let(:path) { "#{CONFIG['source_url']}/cloudupload/#{upload_job.job_id}/_log?nostream=1&start=0" }
        let(:log) { 'lorem ipsum dolorem' }

        before do
          stub_request(:get, path).and_return(body: log)
          get :show, params: { upload_id: upload_job.job_id }
        end

        it { expect(response).to have_http_status(:success) }
        it { expect(response.body).to eq(log) }
      end

      context 'without an upload job' do
        before do
          get :show, params: { upload_id: 42 }
        end

        it { expect(response).to be_redirect }
        it { expect(flash[:error]).not_to be_nil }
      end
    end
  end
end
