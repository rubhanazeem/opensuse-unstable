module Event
  class Request < Base
    self.description = 'Request was updated'
    self.abstract_class = true
    payload_keys :author, :comment, :description, :id, :number, :actions, :state, :when, :who
    shortenable_key :description

    DIFF_LIMIT = 120

    def self.message_number(number)
      "<obs-request-#{number}@#{message_domain}>"
    end

    def my_message_number
      Event::Request.message_number(payload['number'])
    end

    def originator
      payload_address('who')
    end

    def custom_headers
      mid = my_message_number
      h = super
      h['In-Reply-To'] = mid
      h['References'] = mid
      h['X-OBS-Request-Creator'] = payload['author']
      h['X-OBS-Request-Id'] = payload['number']
      h['X-OBS-Request-State'] = payload['state']

      h.merge(headers_for_actions)
    end

    def review_headers
      return { 'X-OBS-Review-By_User' => payload['by_user'] } if payload['by_user']
      return { 'X-OBS-Review-By_Group' => payload['by_group'] } if payload['by_group']
      return { 'X-OBS-Review-By_Package' => "#{payload['by_project']}/#{payload['by_package']}" } if payload['by_package']

      { 'X-OBS-Review-By_Project' => payload['by_project'] }
    end

    def actions_summary
      BsRequest.actions_summary(payload)
    end

    def payload_with_diff
      return payload if source_from_remote? || payload_without_source_project? || payload_without_target_project?

      ret = payload
      payload['actions'].each do |a|
        diff = calculate_diff(a).try(:lines)
        next unless diff

        diff_length = diff.length
        if diff_length > DIFF_LIMIT
          diff = diff[0..DIFF_LIMIT]
          diff << "[cut #{diff_length - DIFF_LIMIT} lines to limit mail size]"
        end
        a['diff'] = diff.join
      end
      ret
    end

    def reviewers
      BsRequest.find_by_number(payload['number']).reviews.map(&:users_and_groups_for_review).flatten.uniq
    end

    def creators
      [User.find_by_login(payload['author'])]
    end

    def target_maintainers
      action_maintainers('targetproject', 'targetpackage')
    end

    def source_maintainers
      action_maintainers('sourceproject', 'sourcepackage')
    end

    def target_watchers
      find_watchers('targetproject')
    end

    def source_watchers
      find_watchers('sourceproject')
    end

    private

    def action_maintainers(prjname, pkgname)
      payload['actions'].map do |action|
        _roles('maintainer', action[prjname], action[pkgname])
      end.flatten.uniq
    end

    def calculate_diff(a)
      return if a['type'] != 'submit'
      raise 'We need action_id' unless a['action_id']

      action = BsRequestAction.find(a['action_id'])
      begin
        action.sourcediff(view: nil, withissues: 0)
      rescue BsRequestAction::Errors::DiffError
        nil # can't help
      end
    end

    def find_watchers(project_key)
      project_names = payload['actions'].map { |action| action[project_key] }.uniq
      watched_projects = WatchedProject.where(project: Project.where(name: project_names))
      User.where(id: watched_projects.select(:user_id))
    end

    def headers_for_actions
      ret = {}
      payload['actions'].each_with_index do |a, index|
        suffix = if payload['actions'].length == 1 || index.zero?
                   'X-OBS-Request-Action'
                 else
                   "X-OBS-Request-Action-#{index}"
                 end

        ret[suffix + '-type'] = a['type']
        if a['targetpackage']
          ret[suffix + '-target'] = "#{a['targetproject']}/#{a['targetpackage']}"
        elsif a['targetrepository']
          ret[suffix + '-target'] = "#{a['targetproject']}/#{a['targetrepository']}"
        elsif a['targetproject']
          ret[suffix + '-target'] = a['targetproject']
        end
        if a['sourcepackage']
          ret[suffix + '-source'] = "#{a['sourceproject']}/#{a['sourcepackage']}"
        elsif a['sourceproject']
          ret[suffix + '-source'] = a['sourceproject']
        end
      end
      ret
    end

    def source_from_remote?
      payload['actions'].any? { |action| Project.unscoped.is_remote_project?(action['sourceproject'], true) }
    end

    def payload_without_target_project?
      payload['actions'].any? { |action| !Project.exists_by_name(action['targetproject']) }
    end

    def payload_without_source_project?
      payload['actions'].any? { |action| !Project.exists_by_name(action['sourceproject']) }
    end
  end
end
