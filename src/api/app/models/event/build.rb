module Event
  class Build < Base
    self.description = 'Package has finished building'
    self.abstract_class = true
    payload_keys :project, :package, :sender, :repository, :arch, :release, :readytime, :srcmd5,
                 :rev, :reason, :bcnt, :verifymd5, :hostarch, :starttime, :endtime, :workerid, :versrel, :previouslyfailed, :successive_failcount, :buildtype

    def custom_headers
      mid = my_message_id
      h = super
      h['In-Reply-To'] = mid
      h['References'] = mid
      h
    end

    def metric_measurement
      'build'
    end

    def metric_tags
      {
        namespace: payload['project'].split(':').first,
        worker: payload['workerid'],
        arch: payload['arch'],
        reason: reason,
        state: state
      }
    end

    def metric_fields
      {
        duration: duration_in_seconds,
        latency: latency_in_seconds
      }
    end

    private

    def duration_in_seconds
      payload['endtime'].to_i - payload['starttime'].to_i
    end

    def latency_in_seconds
      payload['starttime'].to_i - payload['readytime'].to_i
    end

    def reason
      payload['reason'].parameterize.underscore
    end

    def my_message_id
      # we put the verifymd5 sum in the message id, so new checkins get new thread, but it doesn't have to be very correct
      md5 = payload.fetch('verifymd5', 'NOVERIFY')[0..6]
      mid = Digest::MD5.hexdigest("#{payload['project']}-#{payload['package']}-#{payload['repository']}-#{md5}")
      "<build-#{mid}@#{self.class.message_domain}>"
    end
  end
end
