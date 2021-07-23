require 'rails_helper'

RSpec.describe SendEventEmailsJob, type: :job do
  include ActiveJob::TestHelper

  describe '#perform' do
    let(:user) { create(:confirmed_user) }
    let(:group) { create(:group) }
    let(:project) { create(:project, name: 'comment_project', maintainer: [user, group]) }
    let(:comment_author) { create(:confirmed_user) }
    let!(:comment) { create(:comment_project, commentable: project, body: "Hey @#{user.login} how are things?", user: comment_author) }
    let(:user_maintainer) { create(:group) }

    before do
      ActionMailer::Base.deliveries = []
      # Needed for X-OBS-URL
      allow_any_instance_of(Configuration).to receive(:obs_url).and_return('https://build.example.com')
      group.add_user(user)
    end

    context 'with no errors being raised' do
      let!(:subscription1) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user) }
      let!(:subscription2) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user, channel: :rss) }
      let!(:subscription3) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: nil, group: group) }
      let!(:subscription4) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: nil, group: group, channel: :web) }
      let!(:subscription5) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user, channel: :web) }

      subject! { SendEventEmailsJob.new.perform }

      it 'sends an email to the subscribers' do
        email = ActionMailer::Base.deliveries.first

        expect(email.to).to match_array([user.email, group.email])
        expect(email.subject).to include('New comment')
      end

      it "not creates an rss notification for user's email if users doesn't have rss token" do
        expect(Notification.find_by(subscriber: user, rss: true)).to be_nil
      end

      it "creates an web notification for user's email" do
        notification = Notification.find_by(subscriber: user, web: true)

        expect(notification.event_type).to eq('Event::CommentForProject')
        expect(notification.event_payload['comment_body']).to include('how are things?')
        expect(notification.subscription_receiver_role).to eq('maintainer')
        expect(notification.delivered).to be_falsey
      end

      it "creates an web notification with the same raw value of the corresponding event's payload" do
        notification = Notification.find_by(subscriber: user, web: true)
        raw_event_payload = Event::Base.first.attributes_before_type_cast['payload']
        raw_notification_payload = notification.attributes_before_type_cast['event_payload']

        expect(raw_event_payload).to eq(raw_notification_payload)
      end

      it "creates an web notification for group's email" do
        notification = Notification.find_by(subscriber: group, web: true)

        expect(notification.event_type).to eq('Event::CommentForProject')
        expect(notification.event_payload['comment_body']).to include('how are things?')
        expect(notification.subscription_receiver_role).to eq('maintainer')
        expect(notification.delivered).to be_falsey
      end

      it 'only creates two notifications' do
        expect(Notification.count).to eq(2)
      end
    end

    context 'when user has rss token' do
      let!(:subscription) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user, channel: :rss) }

      before do
        user.create_rss_token
      end

      subject! { SendEventEmailsJob.new.perform }

      it "creates an rss notification for user's email" do
        notification = Notification.find_by(subscriber: user, rss: true)

        expect(notification.event_type).to eq('Event::CommentForProject')
        expect(notification.event_payload['comment_body']).to include('how are things?')
        expect(notification.subscription_receiver_role).to eq('maintainer')
        expect(notification.delivered).to be_falsey
      end
    end

    context 'with an error being raised' do
      let!(:subscription1) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: user) }
      let!(:subscription2) { create(:event_subscription_comment_for_project, receiver_role: 'maintainer', user: nil, group: group) }
      let!(:subscription3) { create(:event_subscription_comment_for_project, receiver_role: 'commenter', user: comment_author) }

      before do
        allow(EventMailer).to receive(:event).and_raise(StandardError)
        allow(Airbrake).to receive(:notify)
      end

      subject! { SendEventEmailsJob.new.perform }

      it 'updates the event mails_sent = true' do
        event = Event::CommentForProject.first
        expect(event.mails_sent).to be_truthy
      end

      it 'notifies airbrake' do
        expect(Airbrake).to have_received(:notify)
      end
    end

    context 'with no subscriptions for the event' do
      subject! { SendEventEmailsJob.new.perform }

      it 'updates the event mails_sent = true' do
        event = Event::CommentForProject.first
        expect(event.mails_sent).to be_truthy
      end

      it 'sends no emails' do
        expect(ActionMailer::Base.deliveries.count).to eq(0)
      end
    end
  end
end
