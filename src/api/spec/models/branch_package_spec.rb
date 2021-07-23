require 'rails_helper'

RSpec.describe BranchPackage, vcr: true do
  let(:user) { create(:confirmed_user, :with_home, login: 'tom') }
  let(:home_project) { user.home_project }
  let!(:project) { create(:project, name: 'BaseDistro') }
  let!(:package) { create(:package, name: 'test_package', project: project) }

  describe 'new' do
    context 'with wrong arguments' do
      it {  expect { BranchPackage.new(add_repositories_block: 'foo') }.to raise_error(BranchPackage::Errors::InvalidArgument) }
    end
  end

  describe '#branch' do
    let(:branch_package) { BranchPackage.new(project: project.name, package: package.name) }
    let!(:update_project) { create(:project, name: 'BaseDistro:Update') }
    let(:update_project_attrib) { create(:update_project_attrib, project: project, update_project: update_project) }
    let(:leap_project) { create(:project, name: 'openSUSE_Leap') }
    let(:apache) { create(:package, name: 'apache2', project: leap_project) }
    let(:branch_apache_package) { BranchPackage.new(project: leap_project.name, package: apache.name) }
    let(:dryrun_xml) do
      <<~XML
        <collection>
          <package project=\"BaseDistro:Update\" package=\"test_package\">
            <target project=\"home:tom:branches:BaseDistro:Update\" package=\"test_package\"/>
          </package>
        </collection>
      XML
    end

    before do
      login(user)
      update_project_attrib
    end

    after do
      Project.where('name LIKE ?', "#{user.home_project}:branches:%").destroy_all
    end

    context 'dryrun' do
      let(:branch_package) { BranchPackage.new(project: project.name, package: package.name, dryrun: true) }

      it { expect { branch_package.branch }.not_to(change(Package, :count)) }

      it { expect(branch_package.branch).to include(:content_type, :text) }

      it { expect(branch_package.branch).to include(content_type: 'text/xml', text: dryrun_xml) }
    end

    context 'package with UpdateProject attribute' do
      it 'increases Package by one' do
        expect { branch_package.branch }.to change(Package, :count).by(1)
      end

      it 'creates home:tom:branches:BaseDistro:Update project' do
        branch_package.branch
        expect(Project.where(name: "#{home_project.name}:branches:BaseDistro:Update")).to exist
      end
    end

    context 'project with ImageTemplates attribute' do
      let(:attribute_type) { AttribType.find_by_namespace_and_name!('OBS', 'ImageTemplates') }

      context 'auto cleanup attribute' do
        let!(:image_templates_attrib) { create(:attrib, attrib_type: attribute_type, project: leap_project) }

        it 'is set to 14 if there is no default' do
          branch_apache_package.branch
          project = Project.find_by_name(user.branch_project_name('openSUSE_Leap'))
          expect(14.days.from_now - Time.zone.parse(project.attribs.first.values.first.value)).to be < 1.minute
        end

        it 'is set to the default' do
          allow(Configuration).to receive(:cleanup_after_days).and_return(42)
          branch_apache_package.branch
          project = Project.find_by_name(user.branch_project_name('openSUSE_Leap'))
          expect(42.days.from_now - Time.zone.parse(project.attribs.first.values.first.value)).to be < 1.minute
        end
      end
    end

    context 'project without ImageTemplates attribute' do
      context 'auto cleanup attribute' do
        it 'is set to the default' do
          leap_project
          allow(Configuration).to receive(:cleanup_after_days).and_return(42)
          branch_apache_package.branch
          project = Project.find_by_name(user.branch_project_name('openSUSE_Leap'))
          expect(42.days.from_now - Time.zone.parse(project.attribs.first.values.first.value)).to be < 1.minute
        end

        it 'is not set' do
          branch_apache_package.branch
          project = Project.find_by_name(user.branch_project_name('openSUSE_Leap'))
          expect(project.attribs.length).to eq(0)
        end
      end
    end
  end
end
