require 'rails_helper'
require 'rantly/rspec_extensions'
# WARNING: If you need to make a Backend call uncomment the following line
# CONFIG['global_write_through'] = true

RSpec.describe Project, vcr: true do
  describe 'Staging Project' do
    let(:user) { create(:confirmed_user, :with_home, login: 'tom') }

    let(:managers_group) { create(:group) }
    let(:other_managers_group) { create(:group) }

    let(:staging_workflow) { create(:staging_workflow_with_staging_projects, project: user.home_project, managers_group: managers_group) }
    let(:staging_project) { staging_workflow.staging_projects.first }

    let!(:repository) { create(:repository, architectures: ['x86_64'], project: staging_project, name: 'staging_repository') }
    let!(:repository_arch) { repository.repository_architectures.first }
    let!(:architecture) { repository_arch.architecture }
    let!(:package) { create(:package_with_file, name: 'package_with_file', project: staging_project) }

    let!(:published_report) { create(:status_report, checkable: repository) }
    let!(:build_report) { create(:status_report, checkable: repository_arch) }
    let!(:repository_uuid) { published_report.uuid }
    let!(:build_uuid) { build_report.uuid }

    let(:target_project) { create(:project, name: 'target_project') }
    let(:source_project) { create(:project, :as_submission_source, name: 'source_project') }
    let(:target_package) { create(:package, name: 'target_package', project: target_project) }
    let(:source_package) { create(:package, name: 'source_package', project: source_project) }

    let(:request_attributes) do
      {
        target_package: target_package,
        source_package: source_package
      }
    end

    let(:submit_request) { create(:bs_request_with_submit_action, request_attributes.merge(staging_project: staging_project)) }

    before do
      login(user)
      allow(Backend::Api::Published).to receive(:build_id).with(staging_project.name, repository.name).and_return(repository_uuid)
      allow(Backend::Api::Build::Repository).to receive(:build_id).with(staging_project.name, repository.name, architecture.name).and_return(build_uuid)
    end

    describe '#missing_reviews' do
      let(:other_user) { create(:confirmed_user) }
      let(:other_package) { create(:package) }
      let(:group) { create(:group) }
      let!(:review_1) { create(:review, creator: user, by_user: other_user, bs_request: submit_request) }
      let!(:review_2) { create(:review, creator: user, by_group: group, bs_request: submit_request) }
      let!(:review_3) { create(:review, creator: user, by_project: other_package.project, bs_request: submit_request) }
      let!(:review_4) { create(:review, creator: user, by_package: other_package, by_project: other_package.project, bs_request: submit_request) }

      subject { staging_project.missing_reviews }

      it 'contains all open reviews of staged requests' do
        expect(subject).to contain_exactly(
          { id: review_1.id, request: submit_request.number, state: 'new', package: target_package.name, creator: user.login, by: other_user.login, review_type: 'by_user' },
          { id: review_2.id, request: submit_request.number, state: 'new', package: target_package.name, creator: user.login, by: group.title, review_type: 'by_group' },
          { id: review_3.id, request: submit_request.number, state: 'new', package: target_package.name, creator: user.login, by: other_package.project.name, review_type: 'by_project' },
          { id: review_4.id, request: submit_request.number, state: 'new', package: target_package.name, creator: user.login, by: other_package.name, review_type: 'by_package' }
        )
      end

      context 'when there is an accepted review' do
        before do
          review_2.update(state: 'accepted')
        end

        it { expect(subject.pluck(:id)).not_to include(review_2.id) }
      end
    end

    describe '#untracked_requests' do
      let!(:request_with_review) do
        create(:bs_request_with_submit_action, request_attributes.merge(review_by_project: staging_project))
      end

      it { expect(staging_project.untracked_requests).to contain_exactly(request_with_review) }
    end

    describe '#overall_state' do
      before do
        submit_request
        login(user)
      end

      context 'when there are no staged requests' do
        before do
          submit_request.destroy
        end

        it { expect(staging_project.overall_state).to eq(:empty) }
      end

      context 'when request got revoked' do
        before do
          submit_request.update(state: 'revoked')
        end

        it { expect(staging_project.overall_state).to eq(:unacceptable) }
      end

      context 'when there are missing checks on published repo' do
        before do
          repository.update(required_checks: ['check_1'])
        end

        it { expect(staging_project.overall_state).to eq(:testing) }
      end

      context 'when there are missing checks on build repo' do
        before do
          repository_arch.update(required_checks: ['check_1'])
        end

        it { expect(staging_project.overall_state).to eq(:testing) }
      end

      context 'when there are pending checks' do
        let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'pending') }
        let(:checkable) { published_report.checkable }

        before do
          checkable.required_checks << 'check_1'
          checkable.save
        end

        it { expect(staging_project.overall_state).to eq(:testing) }
      end

      context 'when there are failed checks on published repo' do
        let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'failure') }
        let(:checkable) { published_report.checkable }

        before do
          checkable.required_checks << 'check_1'
          checkable.save
        end

        it { expect(staging_project.overall_state).to eq(:failed) }
      end

      context 'when there are failed checks on build repo' do
        let!(:check) { create(:check, name: 'check_1', status_report: build_report, state: 'failure') }
        let(:checkable) { build_report.checkable }

        before do
          checkable.required_checks << 'check_1'
          checkable.save
        end

        it { expect(staging_project.overall_state).to eq(:failed) }
        it { expect(staging_project.checks).to contain_exactly(check) }
      end

      context 'when there are succeeded checks' do
        let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'success') }

        it { expect(staging_project.overall_state).to eq(:acceptable) }
      end

      context 'when we only have outdated checks' do
        let!(:check) { create(:check, name: 'check_1', status_report: published_report, state: 'failure') }

        before do
          repository.update(required_checks: ['check_1'])
          published_report.update(uuid: 'doesnotmatch')
        end

        it { expect(staging_project.overall_state).to eq(:testing) }
        it { expect(staging_project.missing_checks).to contain_exactly('check_1') }
        it { expect(staging_project.checks).to be_empty }
      end

      context 'with disabled repository' do
        let!(:flag) { create(:build_flag, status: 'disable', project: staging_project, repo: repository.name) }

        it { expect(staging_project.overall_state).to eq(:acceptable) }
      end
    end

    describe '#assign_managers_group' do
      context 'when the group wasn\'t assigned before' do
        before do
          login(user)
          staging_project.assign_managers_group(other_managers_group)
          staging_project.commit_user = user
          staging_project.store
        end

        it { expect(staging_project.reload.groups).to include(other_managers_group) }
      end

      context 'when the group was already assigned' do
        let(:assign_group) do
          staging_project.assign_managers_group(managers_group)
          staging_project.commit_user = user
          staging_project.store
        end

        it { expect { assign_group }.not_to change(Relationship, :count) }
      end
    end

    describe '#unassign_managers_group' do
      before do
        staging_project.unassign_managers_group(managers_group)
        staging_project.commit_user = user
        staging_project.store
      end

      it { expect(staging_project.reload.groups).to be_empty }
    end

    describe '#copy' do
      let(:staging_project) do
        create(:staging_project, staging_workflow: staging_workflow, project_config: 'Prefer: foo', name: "home:#{user}:Staging:XYZ")
      end
      let(:new_project_name) { "#{user.home_project}:new_project" }
      let!(:group_relationship) { create(:relationship_project_group, project: staging_project) }
      let!(:user_relationship) { create(:relationship_project_user, project: staging_project) }
      let!(:flag) { create(:sourceaccess_flag, project: staging_project) }
      # path elements and DoD repository are just needed for smoke testing, e.g. do we have validations or
      # other custom code that would conflict with what 'deep_cloneable' does
      let!(:path_elements) { create_list(:path_element, 3, repository: repository) }
      let!(:dod_repository) { create(:download_repository, repository: repository) }

      subject { staging_project.reload.copy(new_project_name) }

      it 'creates a new staging project' do
        expect(subject).to be_instance_of(Project)
        expect(subject).not_to eq(staging_project)
        expect(subject).to be_persisted
      end

      it { is_expected.to have_attributes(name: new_project_name, staging_workflow_id: staging_workflow.id) }

      it 'copies the project config' do
        expect(subject.config.content).to eq('Prefer: foo')
      end

      it "copies the repositories and it's relations" do
        expect(subject.repositories.pluck(:name)).to eq(staging_project.repositories.pluck(:name))
      end

      it 'copies flags' do
        expect(subject.flags.pluck(:status, :flag)).to eq(staging_project.flags.pluck(:status, :flag))
      end

      it 'copies the relationships' do
        expect(subject.relationships.where(group_relationship.slice(:role_id, :user_id, :group_id))).to exist
        expect(subject.relationships.where(user_relationship.slice(:role_id, :user_id, :group_id))).to exist
      end

      context 'when the repository contains path elements that link to repositories of the same project' do
        let(:other_repository) do
          create(:repository, architectures: ['x86_64'], project: staging_project, name: "#{staging_project.name.tr(':', '_')}_sles_12")
        end
        let!(:path_element) { create(:path_element, repository: repository, link: other_repository) }

        it 'ensures that the new created path is also self referencing' do
          path_elements_of_project = PathElement.where(parent_id: subject.repositories)

          expect(path_elements_of_project.count).to eq(4)
          expect(path_elements_of_project.where(link: staging_project.repositories)).not_to exist
          expect(path_elements_of_project.where(link: subject.repositories)).to exist
        end

        it 'renames the repository link if it contains a reference to the project' do
          expect(PathElement.find_by(parent_id: subject.repositories, link: subject.repositories).link.name).to eq("home_#{user}_new_project_sles_12")
        end
      end
    end
  end
end
