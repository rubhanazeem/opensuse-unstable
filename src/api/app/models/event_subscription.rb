class EventSubscription < ApplicationRecord
  RECEIVER_ROLE_TEXTS = {
    maintainer: 'Maintainer',
    bugowner: 'Bugowner',
    reader: 'Reader',
    source_maintainer: 'Maintainer of the source',
    target_maintainer: 'Maintainer of the target',
    reviewer: 'Reviewer',
    commenter: 'Commenter',
    creator: 'Creator',
    watcher: 'Watching the project',
    source_watcher: 'Watching the source project',
    target_watcher: 'Watching the target project'
  }.freeze

  enum channel: {
    disabled: 0,
    instant_email: 1,
    web: 2,
    rss: 3,
    scm: 4
  }

  # Channels used by the event system, but not meant to be enabled by hand
  INTERNAL_ONLY_CHANNELS = ['scm'].freeze

  serialize :payload, JSON

  belongs_to :user, inverse_of: :event_subscriptions
  belongs_to :group, inverse_of: :event_subscriptions
  belongs_to :token, inverse_of: :event_subscriptions
  belongs_to :package

  validates :receiver_role, inclusion: {
    in: [:maintainer, :bugowner, :reader, :source_maintainer, :target_maintainer,
         :reviewer, :commenter, :creator, :watcher, :source_watcher, :target_watcher]
  }

  scope :for_eventtype, ->(eventtype) { where(eventtype: eventtype) }
  scope :defaults, -> { where(user_id: nil, group_id: nil) }
  scope :for_subscriber, lambda { |subscriber|
    case subscriber
    when User
      where(user: subscriber)
    when Group
      where(group: subscriber)
    else
      defaults
    end
  }

  def subscriber
    if user_id.present?
      user
    elsif group_id.present?
      group
    end
  end

  def subscriber=(subscriber)
    case subscriber
    when User
      self.user = subscriber
    when Group
      self.group = subscriber
    end
  end

  def event_class
    # NOTE: safe_ is required here because for some reason we were getting an uninitialized constant error
    # from this line from the functional tests (though not in rspec or in rails server)
    eventtype.safe_constantize
  end

  def receiver_role
    self[:receiver_role].to_sym
  end

  def parameters_for_notification
    { subscriber: subscriber,
      subscription_receiver_role: receiver_role }
  end

  def self.without_disabled_or_internal_channels
    channels.keys.reject { |channel| channel == 'disabled' || channel.in?(INTERNAL_ONLY_CHANNELS) }
  end
end

# == Schema Information
#
# Table name: event_subscriptions
#
#  id            :integer          not null, primary key
#  channel       :integer          default("disabled"), not null
#  enabled       :boolean          default(FALSE)
#  eventtype     :string(255)      not null
#  payload       :text(65535)
#  receiver_role :string(255)      not null
#  created_at    :datetime
#  updated_at    :datetime
#  group_id      :integer          indexed
#  package_id    :integer          indexed
#  token_id      :integer          indexed
#  user_id       :integer          indexed
#
# Indexes
#
#  index_event_subscriptions_on_group_id    (group_id)
#  index_event_subscriptions_on_package_id  (package_id)
#  index_event_subscriptions_on_token_id    (token_id)
#  index_event_subscriptions_on_user_id     (user_id)
#
