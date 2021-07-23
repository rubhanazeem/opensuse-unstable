class FullTextSearch
  include ActiveModel::Serializers::JSON

  LINKED_COUNT_WEIGHT = 100
  ACTIVITY_INDEX_WEIGHT = 500
  LINKS_TO_OTHER_WEIGHT = -1000
  IS_DEVEL_WEIGHT = 1000
  FIELD_WEIGHTS = { name: 10, title: 2, description: 1 }.freeze
  RANKER = :sph04
  PER_PAGE = 50
  STAR = false
  MAX_MATCHES = 15_000

  attr_accessor :text, :classes, :fields, :attrib_type_id, :issue_tracker_name, :issue_name
  attr_reader :result

  def initialize(attrib = {})
    if attrib
      attrib.each do |att, value|
        send(:"#{att}=", value)
      end
    end
    @result = nil
  end

  def search(options = {})
    args = { ranker: RANKER,
             star: STAR,
             max_matches: MAX_MATCHES,
             order: 'adjusted_weight DESC',
             field_weights: FIELD_WEIGHTS,
             page: options[:page],
             per_page: options[:per_page] || PER_PAGE,
             without: { project_id: Relationship.forbidden_project_ids } }

    args[:select] = '*, (weight() + '\
                    "#{LINKED_COUNT_WEIGHT} * linked_count + "\
                    "#{LINKS_TO_OTHER_WEIGHT} * links_to_other + "\
                    "#{IS_DEVEL_WEIGHT} * is_devel + "\
                    "#{ACTIVITY_INDEX_WEIGHT} * (activity_index * POW( 2.3276, (updated_at - #{Time.now.to_i}) / 10000000))) "\
                    'as adjusted_weight'

    issue_id = find_issue_id
    if issue_id || attrib_type_id
      args[:with] = {}
      args[:with][:issue_ids] = issue_id.to_i unless issue_id.nil?
      args[:with][:attrib_type_ids] = attrib_type_id.to_i unless attrib_type_id.nil?
    end
    args[:classes] = classes.map { |i| i.to_s.classify.constantize } if classes

    @result = ThinkingSphinx.search(search_str, args)
  end

  # Needed by ActiveModel::Serializers
  def attributes
    { 'text' => nil, 'classes' => nil, 'fields' => nil, 'attrib_type_id' => nil,
      'issue_tracker_name' => nil, 'issue_name' => nil,
      'result' => nil, 'total_entries' => nil }
  end

  private

  def search_str
    if text.blank?
      nil
    elsif fields.blank?
      Riddle::Query.escape(text)
    else
      "@(#{fields.map(&:to_s).join(',')}) #{Riddle::Query.escape(text)}"
    end
  end

  def find_issue_id
    return unless issue_tracker_name && issue_name

    # compat code for handling all writings of CVE id's
    issue_name.gsub!(/^CVE-/i, '') if issue_tracker_name == 'cve'
    # Return 0 if the issue does not exist in order to force an empty result
    Issue.joins(:issue_tracker).where('issue_trackers.name' => issue_tracker_name, :name => issue_name).pick(:id) || 0
  end
end
