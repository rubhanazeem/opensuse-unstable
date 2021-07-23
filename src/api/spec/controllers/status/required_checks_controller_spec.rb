require 'rails_helper'

RSpec.describe Status::RequiredChecksController, type: :controller do
  let(:user) { create(:confirmed_user) }
  let(:repository) { create(:repository) }
  let(:repository_architecture) { create(:repository_architecture, repository: repository) }
  let(:project) { create(:project, repositories: [repository]) }

  describe 'GET index' do
    shared_context 'it renders index' do
      context 'with required checks' do
        before do
          checkable.update!(required_checks: ['first check', 'second check'])
          get :index, params: params, format: :xml
        end

        it { expect(assigns(:required_checks)).to include('first check') }
        it { expect(assigns(:required_checks)).to include('second check') }
        it { expect(response).to have_http_status(:success) }
      end

      context 'without required checks' do
        before do
          get :index, params: params, format: :xml
        end

        it { expect(assigns(:required_checks)).to be_empty }
        it { expect(response).to have_http_status(:success) }
      end
    end

    shared_context 'required check' do
      context 'for a logged-in user' do
        before do
          login(user)
        end

        include_context 'it renders index'
      end

      context 'for an anonymous user' do
        include_context 'it renders index'
      end
    end

    context 'for repository' do
      let(:checkable) { repository }
      let(:params) { { project_name: project.name, repository_name: repository.name } }

      include_context 'required check'
    end

    context 'for repository_architecture' do
      let(:checkable) { repository_architecture }
      let(:params) { { project_name: project.name, repository_name: repository.name, architecture_name: repository_architecture.architecture.name } }

      include_context 'required check'
    end
  end

  describe 'POST create' do
    let(:required_check_xml) do
      file_fixture('required_check.xml').read
    end

    shared_examples 'does create a required check' do
      subject { post :create, body: required_check_xml, params: params, format: :xml }

      it 'will create a required check' do
        expect { subject }.to change {
          # we need to to reload because required_checks is a serialized attribute
          checkable.reload
          checkable.required_checks.count
        }.by(example_count)
      end

      it { is_expected.to have_http_status(:success) }
    end

    shared_examples 'does not create a required check' do
      it 'will not create a required check' do
        expect do
          post :create, body: required_check_xml, params: params, format: :xml
        end.not_to(
          change do
            # we need to to reload because required_checks is a serialized attribute
            checkable.reload
            checkable.required_checks.count
          end
        )
      end
    end

    shared_examples 'returns correct status' do
      before do
        post :create, body: required_check_xml, params: params, format: :xml
      end

      it 'has correct HTTP status' do
        expect(response).to have_http_status(status)
      end
    end

    shared_context 'for logged in user' do
      before do
        login(user)
      end

      context 'with user permission' do
        let!(:relationship) { create(:relationship_project_user, user: user, project: project) }

        context 'with one required check' do
          let(:example_count) { 1 }

          include_context 'does create a required check'
        end

        context 'with more one required check' do
          let(:required_check_xml) do
            file_fixture('required_checks.xml').read
          end
          let(:example_count) { 2 }

          include_context 'does create a required check'
        end
      end

      context 'with group permission' do
        let(:example_count) { 1 }
        let(:group_with_user) { create(:group_with_user) }
        let(:user) { group_with_user.users.first }
        let!(:relationship) { create(:relationship_project_group, group: group_with_user, project: project) }

        include_context 'does create a required check'
      end

      context 'without permission' do
        let(:status) { :forbidden }

        include_context 'does not create a required check'
        include_context 'returns correct status'
      end
    end

    shared_context 'with additional elements in body' do
      let!(:relationship) { create(:relationship_project_user, user: user, project: project) }
      let(:example_count) { 1 }
      let(:required_check_xml) do
        file_fixture('required_check_with_additional_params.xml').read
      end

      before do
        login(user)
      end

      include_context 'does create a required check'
    end

    shared_context 'for an anonymous user' do
      let(:status) { :unauthorized }
      include_context 'does not create a required check'
      include_context 'returns correct status'
    end

    context 'for repository' do
      let(:checkable) { repository }
      let(:params) { { project_name: project.name, repository_name: repository.name } }

      it_behaves_like 'for logged in user'
      it_behaves_like 'with additional elements in body'
      it_behaves_like 'for an anonymous user'
    end

    context 'for repository_architecture' do
      let(:checkable) { repository_architecture }
      let(:params) { { project_name: project.name, repository_name: repository.name, architecture_name: repository_architecture.architecture.name } }

      it_behaves_like 'for logged in user'
      it_behaves_like 'with additional elements in body'
      it_behaves_like 'for an anonymous user'
    end
  end

  describe 'DELETE destroy' do
    before do
      checkable.required_checks = ['first check', 'second check']
      checkable.save
    end

    shared_examples 'does delete the required check' do
      subject do
        delete :destroy, params: params.merge(name: 'first check'), format: :xml
      end

      it 'will delete the required check' do
        expect { subject }.to change {
          # we need to to reload because required_checks is a serialized attribute
          checkable.reload
          checkable.required_checks.count
        }.by(-1)
      end

      it { is_expected.to have_http_status(:success) }
    end

    shared_examples 'does not delete the required check' do
      it 'will not delete the required check' do
        expect do
          delete :destroy, params: params.merge(name: 'first check'), format: :xml
        end.not_to(
          change do
            # we need to to reload because required_checks is a serialized attribute
            checkable.reload
            checkable.required_checks.count
          end
        )
      end
    end

    shared_examples 'returns correct status' do
      before do
        delete :destroy, params: { project_name: project.name,
                                   repository_name: repository.name,
                                   name: 'first check' }, format: :xml
      end

      it 'has correct HTTP status' do
        expect(response).to have_http_status(status)
      end
    end

    shared_context 'for logged in user' do
      before do
        login(user)
      end

      context 'with user permissions' do
        let!(:relationship) { create(:relationship_project_user, user: user, project: project) }

        include_context 'does delete the required check'
      end

      context 'with group permissions' do
        let(:group_with_user) { create(:group_with_user) }
        let(:user) { group_with_user.users.first }
        let!(:relationship) { create(:relationship_project_group, group: group_with_user, project: project) }

        include_context 'does delete the required check'
      end

      context 'without permissions' do
        let(:status) { :forbidden }

        include_context 'does not delete the required check'
        include_context 'returns correct status'
      end
    end

    shared_context 'for an anonymous user' do
      let(:status) { :unauthorized }
      include_context 'does not delete the required check'
      include_context 'returns correct status'
    end

    context 'for repository' do
      let(:checkable) { repository }
      let(:params) { { project_name: project.name, repository_name: repository.name } }

      it_behaves_like 'for logged in user'
      it_behaves_like 'for an anonymous user'
    end

    context 'for repository_architecture' do
      let(:checkable) { repository_architecture }
      let(:params) { { project_name: project.name, repository_name: repository.name, architecture_name: repository_architecture.architecture.name } }

      it_behaves_like 'for logged in user'
      it_behaves_like 'for an anonymous user'
    end
  end
end
