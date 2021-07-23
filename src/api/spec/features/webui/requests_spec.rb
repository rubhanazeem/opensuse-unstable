require 'browser_helper'

RSpec.describe 'Bootstrap_Requests', type: :feature, js: true, vcr: true do
  let(:submitter) { create(:confirmed_user, :with_home, login: 'kugelblitz') }
  let(:receiver) { create(:confirmed_user, :with_home, login: 'titan') }
  let(:target_project) { receiver.home_project }
  let(:target_package) { create(:package, name: 'goal', project_id: target_project.id) }
  let(:source_project) { submitter.home_project }
  let(:source_package) { create(:package, name: 'ball', project_id: source_project.id) }
  let(:bs_request) { create(:delete_bs_request, target_project: target_project, description: 'a long text - ' * 200, creator: submitter) }

  RSpec.shared_examples 'expandable element' do
    it 'expanding a text field' do
      visit request_show_path(bs_request)
      within(element) do
        find('.show-content').click
        expect(page).to have_css('div.expanded')
        find('.show-content').click
        expect(page).to have_no_css('div.expanded')
      end
    end
  end

  context 'request show page' do
    let!(:superseded_bs_request) { create(:superseded_bs_request, superseded_by_request: bs_request) }
    let!(:comment_1) { create(:comment, commentable: bs_request) }
    let!(:comment_2) { create(:comment, commentable: superseded_bs_request) }

    it 'show request comments' do
      visit request_show_path(bs_request)
      expect(page).to have_text(comment_1.body)
      expect(page).not_to have_text(comment_2.body)
      find('a', text: "Comments for request #{superseded_bs_request.number}").click
      expect(page).to have_text(comment_2.body)
      expect(page).not_to have_text(comment_1.body)
    end

    describe 'request description field' do
      it 'superseded requests' do
        visit request_show_path(bs_request)
        within 'li', text: "Supersedes #{superseded_bs_request.number}" do
          find('a', text: superseded_bs_request.number).click
        end
        expect(page).to have_text('In state superseded')
        within 'li', text: "Superseded by #{bs_request.number}" do
          find('a', text: bs_request.number)
        end
      end

      it_behaves_like 'expandable element' do
        let(:element) { '#description-text' }
      end
    end

    describe 'request history entries' do
      it_behaves_like 'expandable element' do
        let(:element) { '.media-body .obs-collapsible-textbox' }
      end
    end
  end

  context 'for role addition group' do
    describe 'for projects' do
      let(:roleaddition_group) { create(:group) }

      it 'can be submitted' do
        login submitter
        visit project_show_path(project: target_project)
        desktop? ? click_link('Request Role Addition') : click_menu_link('Actions', 'Request Role Addition')
        choose 'Bugowner'
        choose 'Group'
        fill_in 'Group:', with: roleaddition_group.title
        fill_in 'Description:', with: 'I can fix bugs too.'
        expect { click_button('Request') }.to change(BsRequest, :count).by(1)
        expect(page).to have_text("#{submitter.realname} (#{submitter.login}) wants the group #{roleaddition_group} to get the role bugowner for project #{target_project}")
        expect(page).to have_css('#description-text', text: 'I can fix bugs too.')
        expect(page).to have_text('In state new')
      end

      it 'can be accepted' do
        bs_request.bs_request_actions.delete_all
        create(:bs_request_action_add_bugowner_role, target_project: target_project,
                                                     person_name: submitter,
                                                     bs_request_id: bs_request.id)
        login receiver
        visit request_show_path(bs_request)
        click_button 'Accept'

        expect(page).to have_text("Request #{bs_request.number}")
        expect(find('span.badge.badge-success')).to have_text('accepted')
        expect(page).to have_text('In state accepted')
      end
    end

    describe 'for packages' do
      let(:roleaddition_group) { create(:group) }
      let(:bs_request) do
        create(:add_maintainer_request, target_package: target_package,
                                        description: 'a long text - ' * 200,
                                        creator: submitter,
                                        person_name: submitter)
      end

      it 'can be submitted' do
        login submitter
        visit package_show_path(project: target_project, package: target_package)
        desktop? ? click_link('Request Role Addition') : click_menu_link('Actions', 'Request Role Addition')
        choose 'Maintainer'
        choose 'Group'
        fill_in 'Group:', with: roleaddition_group.title
        fill_in 'Description:', with: 'I can produce bugs too.'
        expect { click_button('Request') }.to change(BsRequest, :count).by(1)

        expect(page).to have_text("#{submitter.realname} (#{submitter.login}) wants the group #{roleaddition_group.title} to get the role maintainer " \
                                  "for package #{target_project} / #{target_package}")
        expect(page).to have_css('#description-text', text: 'I can produce bugs too.')
        expect(page).to have_text('In state new')
      end

      it 'can be accepted' do
        login receiver
        visit request_show_path(bs_request)
        click_button 'Accept'

        expect(page).to have_text("Request #{bs_request.number}")
        expect(find('span.badge.badge-success')).to have_text('accepted')
        expect(page).to have_text('In state accepted')
      end
    end
  end

  context 'for role addition user' do
    describe 'for projects' do
      it 'can be submitted' do
        login submitter
        visit project_show_path(project: target_project)
        desktop? ? click_link('Request Role Addition') : click_menu_link('Actions', 'Request Role Addition')
        choose 'Bugowner'
        choose 'User'
        fill_in 'User:', with: "#{submitter.login}"
        fill_in 'Description:', with: 'I can fix bugs too.'
        expect { click_button('Request') }.to change(BsRequest, :count).by(1)
        expect(page).to have_text("#{submitter.realname} (#{submitter.login}) wants to get the role bugowner for project #{target_project}")
        expect(page).to have_css('#description-text', text: 'I can fix bugs too.')
        expect(page).to have_text('In state new')
      end

      it 'can be accepted' do
        bs_request.bs_request_actions.delete_all
        create(:bs_request_action_add_bugowner_role, target_project: target_project,
                                                     person_name: submitter,
                                                     bs_request_id: bs_request.id)
        login receiver
        visit request_show_path(bs_request)
        click_button 'Accept'

        expect(page).to have_text("Request #{bs_request.number}")
        expect(find('span.badge.badge-success')).to have_text('accepted')
        expect(page).to have_text('In state accepted')
      end
    end

    describe 'for packages' do
      let(:bs_request) do
        create(:add_maintainer_request, target_package: target_package,
                                        description: 'a long text - ' * 200,
                                        creator: submitter,
                                        person_name: submitter)
      end

      it 'can be submitted' do
        login submitter
        visit package_show_path(project: target_project, package: target_package)
        desktop? ? click_link('Request Role Addition') : click_menu_link('Actions', 'Request Role Addition')
        choose 'Maintainer'
        choose 'User'
        fill_in 'User:', with: submitter.login
        fill_in 'Description:', with: 'I can produce bugs too.'
        expect { click_button('Request') }.to change(BsRequest, :count).by(1)
        expect(page).to have_text("#{submitter.realname} (#{submitter.login}) wants to get the role maintainer " \
                                  "for package #{target_project} / #{target_package}")
        expect(page).to have_css('#description-text', text: 'I can produce bugs too.')
        expect(page).to have_text('In state new')
      end

      it 'can be accepted' do
        login receiver
        visit request_show_path(bs_request)
        click_button 'Accept'

        expect(page).to have_text("Request #{bs_request.number}")
        expect(find('span.badge.badge-success')).to have_text('accepted')
        expect(page).to have_text('In state accepted')
      end
    end
  end

  context 'review' do
    describe 'for user' do
      let(:reviewer) { create(:confirmed_user) }

      it 'opens a review and accepts it' do
        login submitter
        visit request_show_path(bs_request)
        desktop? ? click_link('Add a Review') : click_menu_link('Actions', 'Add a Review')
        find(:id, 'review_type').select('User')
        fill_in 'review_user', with: reviewer.login
        fill_in 'Comment for reviewer:', with: 'Please review'
        click_button('Accept')
        expect(page).to have_text(/Open review for\s+#{reviewer.login}/)
        expect(page).to have_text('Request 1')
        expect(find('span.badge.badge-secondary')).to have_text('review')
        expect(page).to have_text('In state review')
        expect(Review.all.count).to eq(1)
        logout

        login reviewer
        visit request_show_path(1)
        click_link("Review for #{reviewer}")
        within '#review-0' do
          fill_in 'comment', with: 'Ok for the project'
          click_button 'Approve'
        end
        expect(page).to have_text('Ok for the project')
        expect(Review.first.state).to eq(:accepted)
        expect(BsRequest.first.state).to eq(:new)
      end
    end

    describe 'for group' do
      let(:review_group) { create(:group) }

      it 'opens a review' do
        login submitter
        visit request_show_path(bs_request)
        desktop? ? click_link('Add a Review') : click_menu_link('Actions', 'Add a Review')
        find(:id, 'review_type').select('Group')
        fill_in 'review_group', with: review_group.title
        click_button('Accept')
        expect(page).to have_text("Open review for #{review_group.title}")
      end
    end

    describe 'for project' do
      it 'opens a review' do
        login submitter
        visit request_show_path(bs_request)
        desktop? ? click_link('Add a Review') : click_menu_link('Actions', 'Add a Review')
        find(:id, 'review_type').select('Project')
        fill_in 'review_project', with: submitter.home_project
        click_button('Accept')
        expect(page).to have_text("Open review for #{submitter.home_project}")
      end
    end

    describe 'for package' do
      let(:package) { create(:package, project: submitter.home_project) }

      it 'opens a review' do
        login submitter
        visit request_show_path(bs_request)
        desktop? ? click_link('Add a Review') : click_menu_link('Actions', 'Add a Review')
        find(:id, 'review_type').select('Package')
        fill_in 'review_project', with: submitter.home_project
        fill_in 'review_package', with: package.name
        click_button('Accept')
        expect(page).to have_text("Open review for #{submitter.home_project} / #{package.name}")
      end
    end

    describe 'for invalid reviewer' do
      it 'opens no review' do
        login submitter
        visit request_show_path(bs_request)
        desktop? ? click_link('Add a Review') : click_menu_link('Actions', 'Add a Review')
        find(:id, 'review_type').select('Project')
        fill_in 'review_project', with: 'INVALID/PROJECT'
        click_button('Accept')
        expect(page).to have_css('#flash', text: 'Unable add review to')
      end
    end

    describe 'for reviewer' do
      let(:review_group) { create(:group) }
      let(:reviewer) { create(:confirmed_user) }

      before do
        review_group.users << reviewer
        review_group.save!
      end

      context 'for project reviews' do
        before do
          create(:review, by_group: review_group, bs_request: bs_request)
        end

        it 'does not show any request reason' do
          login reviewer
          visit request_show_path(bs_request)
          expect(find('#review-0')).not_to have_text('requested:')
        end
      end

      context 'for manual reviews' do
        before do
          create(:review, by_group: review_group, bs_request: bs_request, creator: receiver, reason: 'Does this make sense?')
        end

        it 'shows request reason' do
          login reviewer
          visit request_show_path(bs_request)
          within '#review-0' do
            expect(page).to have_text("#{receiver.realname} (#{receiver.login}) requested:\nDoes this make sense?")
          end
        end
      end
    end
  end

  describe 'shows the correct auto accepted message' do
    before do
      bs_request.update(accept_at: Time.now)
    end

    it 'when request is in a final state' do
      bs_request.update(state: :accepted)
      visit request_show_path(bs_request)
      expect(page).to have_text("Auto-accept was set to #{I18n.l(bs_request.accept_at, format: :only_date)}.")
    end

    it 'when request auto_accept is in the past and not in a final state' do
      visit request_show_path(bs_request)
      expect(page).to have_text("This request will be automatically accepted when it enters the 'new' state.")
    end

    it 'when request auto_accept is in the future and not in a final state' do
      bs_request.update(accept_at: Time.now + 1.day)
      visit request_show_path(bs_request)
      expect(page)
        .to have_text("This request will be automatically accepted in #{ApplicationController.helpers.time_ago_in_words(bs_request.accept_at)}.")
    end
  end
end
