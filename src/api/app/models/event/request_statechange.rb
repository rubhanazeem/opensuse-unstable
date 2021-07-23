module Event
  class RequestStatechange < Request
    self.message_bus_routing_key = 'request.state_change'
    self.description = 'Request state was changed'
    payload_keys :oldstate
    receiver_roles :source_maintainer, :target_maintainer, :creator, :reviewer, :source_watcher, :target_watcher

    def subject
      "Request #{payload['number']} changed from #{payload['oldstate']} to #{payload['state']} (#{actions_summary})"
    end

    def parameters_for_notification
      super.merge({ notifiable_type: 'BsRequest',
                    bs_request_state: payload['state'],
                    bs_request_oldstate: payload['oldstate'] })
    end

    private

    def metric_tags
      payload.slice('oldstate', 'state')
    end

    def metric_fields
      payload.slice('number')
    end
  end
end

# == Schema Information
#
# Table name: events
#
#  id          :integer          not null, primary key
#  eventtype   :string(255)      not null, indexed
#  mails_sent  :boolean          default(FALSE), indexed
#  payload     :text(65535)
#  undone_jobs :integer          default(0)
#  created_at  :datetime         indexed
#  updated_at  :datetime
#
# Indexes
#
#  index_events_on_created_at  (created_at)
#  index_events_on_eventtype   (eventtype)
#  index_events_on_mails_sent  (mails_sent)
#
