class EventSubscription
  class ForChannelForm
    DISABLE_FOR_EVENTS = ['Event::BuildFail', 'Event::ServiceFail'].freeze

    attr_reader :name, :subscription

    delegate :enabled?, to: :subscription

    def initialize(channel_name, subscription, event)
      @name = channel_name
      @subscription = subscription
      @event = event
    end

    def subscription_params(index)
      @index = index
      "#{subscription_channel_param}&#{subscription_eventtype_param}&#{subscription_receiver_role_param}"
    end

    def disabled_checkbox?
      DISABLE_FOR_EVENTS.include?(@event.to_s) && (name == 'web' || name == 'rss')
    end

    private

    def subscription_channel_param
      "subscriptions[#{@index}][channel]=#{name}"
    end

    def subscription_eventtype_param
      "subscriptions[#{@index}][eventtype]=#{subscription.eventtype}"
    end

    def subscription_receiver_role_param
      "subscriptions[#{@index}][receiver_role]=#{subscription.receiver_role}"
    end
  end
end
