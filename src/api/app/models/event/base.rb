# This class represents some kind of event within the build service
# that users (or services) would like to know about
module Event
  class Base < ApplicationRecord
    self.inheritance_column = 'eventtype'
    self.table_name = 'events'

    after_create :create_project_log_entry_job, if: -> { (PROJECT_CLASSES | PACKAGE_CLASSES).include?(self.class.name) }

    EXPLANATION_FOR_NOTIFICATIONS =  {
      'Event::BuildFail' => 'Receive notifications of build failures for packages for which you are...',
      'Event::ServiceFail' => 'Receive notifications of source service failures for packages for which you are...',
      'Event::ReviewWanted' => 'Receive notifications of reviews created that have you as a wanted...',
      'Event::RequestCreate' => 'Receive notifications of requests created for projects/packages for which you are...',
      'Event::RequestStatechange' => 'Receive notifications of requests state changes for projects for which you are...',
      'Event::CommentForProject' => 'Receive notifications of comments created on projects for which you are...',
      'Event::CommentForPackage' => 'Receive notifications of comments created on a package for which you are...',
      'Event::CommentForRequest' => 'Receive notifications of comments created on a request for which you are...'
    }.freeze

    class << self
      attr_accessor :description, :message_bus_routing_key

      @payload_keys = nil
      @create_jobs = nil
      @classnames = nil
      @receiver_roles = nil
      @shortenable_key = nil

      def notification_events
        ['Event::BuildFail', 'Event::ServiceFail', 'Event::ReviewWanted', 'Event::RequestCreate',
         'Event::RequestStatechange', 'Event::CommentForProject', 'Event::CommentForPackage',
         'Event::CommentForRequest'].map(&:constantize)
      end

      def classnames
        @classnames || [name]
      end

      def add_classname(name)
        @classnames ||= [self.name]
        @classnames << name
      end

      def payload_keys(*keys)
        # this function serves both for reading and setting
        return @payload_keys if keys.empty?

        @payload_keys ||= []
        @payload_keys += keys
      end

      # FIXME: Find a way to get rid of these setter/getter methods for all these class variables
      def shortenable_key(key = nil)
        # this function serves both for reading and setting
        return @shortenable_key if key.nil?

        @shortenable_key = key
      end

      def create_jobs(*keys)
        # this function serves both for reading and setting
        return @create_jobs || [] if keys.empty?

        @create_jobs ||= []
        @create_jobs += keys
      end

      def receiver_roles(*keys)
        # this function serves both for reading and setting
        return @receiver_roles || [] if keys.empty?

        @receiver_roles ||= []
        @receiver_roles += keys
      end

      # make sure that subclasses can set shared attributes
      def inherited(subclass)
        super

        subclass.after_create_commit(:send_to_bus)
        subclass.after_create_commit(:clear_caches)
        subclass.add_classname(name) unless name == 'Event::Base'
        subclass.payload_keys(*payload_keys)
        subclass.create_jobs(*create_jobs)
        subclass.receiver_roles(*receiver_roles)
      end
    end

    # just for convenience
    def payload_keys
      self.class.payload_keys
    end

    def shortenable_key
      self.class.shortenable_key
    end

    def create_jobs
      self.class.create_jobs
    end

    def receiver_roles
      self.class.receiver_roles
    end

    def initialize(attribs)
      attributes = attribs.dup.with_indifferent_access
      super()
      self.created_at = attribs[:time] if attributes[:time]
      attributes.delete :eventtype
      attributes.delete :time

      set_payload(attributes, payload_keys)
    end

    def check_left_attribs(attribs)
      # remove default rails params
      attribs.delete 'format'
      attribs.delete 'action'
      attribs.delete 'controller'

      return if attribs.empty?

      na = []
      attribs.keys.each { |k| na << k.to_s }
      logger.debug "LEFT #{self.class.name} payload_keys :#{na.sort.join(', :')}"
      raise "LEFT #{self.class.name} payload_keys :#{na.sort.join(', :')} # #{attribs.inspect}"
    end

    def set_payload(attribs, keys)
      values = {}
      keys.each do |k|
        # for internal events it's a symbol, for external ones a string, so try both
        v = attribs.delete k
        k = k.to_s
        v ||= attribs.delete k
        values[k] = v unless v.nil?
      end
      self.payload = ActiveSupport::JSON.encode(calculate_payload(values))
      # now check if anything but the default rails params are left
      check_left_attribs(attribs)
    end

    def payload
      @payload ||= ActiveSupport::JSON.decode(self[:payload])
    end

    def create_project_log_entry_job
      CreateProjectLogEntryJob.perform_later(payload, created_at.to_s, self.class.name)
    end

    after_create :perform_create_jobs

    def perform_create_jobs
      self.undone_jobs = 0
      save
      create_jobs.each do |job|
        job_class = job.to_s.camelize.safe_constantize
        raise "#{job.to_s.camelize} does not map to a constant" if job_class.nil?

        job_obj = job_class.new
        raise("#{job.to_s.camelize} is not a CreateJob") unless job_obj.is_a?(CreateJob)

        job_class.perform_later(id)

        self.undone_jobs += 1
      end
      save if self.undone_jobs.positive?
    end

    def mark_job_done!
      return unless undone_jobs.positive?

      self.undone_jobs -= 1
      save!
    end

    # to be overwritten in subclasses
    def subject
      'Build Service Notification'
    end

    def self.message_domain
      domain = URI.parse(::Configuration.obs_url)
      domain.host.downcase
    end

    # needs to return a hash (merge super)
    def custom_headers
      # not to break user's filters for now
      ret = {}
      ret['X-OBS-event-type'] = template_name # cheating
      ret['Message-ID'] = if Rails.env.test?
                            "<notrandom@#{self.class.message_domain}>"
                          else
                            "<#{Mail.random_tag}@#{self.class.message_domain}>"
                          end
      ret
    end

    def subscriptions(channel = :instant_email)
      EventSubscription::FindForEvent.new(self).subscriptions(channel)
    end

    def subscribers
      subscriptions.map(&:subscriber)
    end

    # to calculate expensive things we don't want to store in database (i.e. diffs)
    def expanded_payload
      payload
    end

    def payload_address(field)
      return User.find_by_login(payload[field]) if payload[field]

      nil
    end

    def originator
      payload_address('sender')
    end

    def template_name
      self.class.name.gsub('Event::', '').underscore
    end

    def maintainers
      Rails.logger.debug { "Maintainers #{payload.inspect}" }
      ret = _roles('maintainer', payload['project'], payload['package'])
      Rails.logger.debug { "Maintainers ret #{ret.inspect}" }
      ret
    end

    def bugowners
      Rails.logger.debug { "Maintainers #{payload.inspect}" }
      ret = _roles('bugowner', payload['project'], payload['package'])
      Rails.logger.debug { "Maintainers ret #{ret.inspect}" }
      ret
    end

    def readers
      Rails.logger.debug { "Readers #{payload.inspect}" }
      ret = _roles('reader', payload['project'])
      Rails.logger.debug { "Readers ret #{ret.inspect}" }
      ret
    end

    def watchers
      project = ::Project.find_by_name(payload['project'])
      return [] if project.blank?

      project.watched_projects.map(&:user)
    end

    def _roles(role, project, package = nil)
      return [] unless project

      p = nil
      p = ::Package.find_by_project_and_name(project, package) if package
      p ||= ::Project.find_by_name(project)
      obj_roles(p, role)
    end

    def send_to_bus
      RabbitmqBus.send_to_bus(message_bus_routing_key, self[:payload]) if message_bus_routing_key
      RabbitmqBus.send_to_bus('metrics', to_metric) if metric_fields.present?
    end

    def clear_caches
      # no default implementation
    end

    def parameters_for_notification
      { event_type: eventtype,
        event_payload: payload,
        notifiable_id: payload['id'],
        created_at: payload['when'].to_datetime,
        title: subject_to_title }
    end

    private

    def message_bus_routing_key
      self.class.message_bus_routing_key
    end

    def metric_tags
      {}
    end

    def metric_fields
      {}
    end

    def metric_measurement
      message_bus_routing_key
    end

    def to_metric
      tags = metric_tags.map { |k, v| "#{k}=#{v}" }.join(',')
      tags = ",#{tags}" if tags.present?
      fields = metric_fields.map { |k, v| "#{k}=#{v}" }.join(',')
      "#{metric_measurement}#{tags} #{fields}"
    end

    def calculate_payload(values)
      return values if shortenable_key.nil? # If no shortenable_key is set then we cannot shorten the payload

      overflow_bytes = ActiveSupport::JSON.encode(values).bytesize - 65_535

      return values if overflow_bytes <= 0

      # Shorten the payload so it will fit into the database column
      shortenable_content = values[shortenable_key.to_s]
      new_size = shortenable_content.bytesize - overflow_bytes
      values[shortenable_key.to_s] = shortenable_content.mb_chars.limit(new_size)

      values
    end

    def obj_roles(obj, role)
      # old/deleted obj
      return [] unless obj || role.blank?

      rel = obj.relationships.where(role: Role.hashed[role])
      receivers = rel.map { |r| r.user_id ? r.user : r.group }
      receivers = obj_roles(obj.project, role) if receivers.empty? && obj.respond_to?(:project)

      # for now we define develpackage maintainers as being maintainers too
      receivers.concat(obj_roles(obj.develpackage, role)) if obj.respond_to?(:develpackage)
      receivers
    end

    def subject_to_title
      return subject if subject.size <= 255

      subject.slice(0, 252).concat('...')
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
