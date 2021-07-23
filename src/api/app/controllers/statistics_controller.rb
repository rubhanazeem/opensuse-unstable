require 'statistics_calculations'

class StatisticsController < ApplicationController
  validate_action redirect_stats: { method: :get, response: :redirect_stats }

  before_action :get_limit, only: [
    :highest_rated, :most_active_packages, :most_active_projects, :latest_added, :latest_updated,
    :download_counter
  ]

  def index
    render plain: 'This is the statistics controller.<br/>See the api documentation for details.'
  end

  def min_votes_for_rating
    CONFIG['min_votes_for_rating']
  end

  def highest_rated
    # set automatic action_cache expiry time limit
    # response.time_to_live = 10.minutes

    ratings = Rating.select('db_object_id, db_object_type, count(score) as count,' \
                            'sum(score)/count(score) as score_calculated').group('db_object_id, db_object_type').order('score_calculated DESC')
    ratings = ratings.to_a.delete_if { |r| r.count.to_i < min_votes_for_rating }
    @ratings = if @limit
                 ratings[0..@limit - 1]
               else
                 ratings
               end
  end

  def rating
    @project = params[:project]
    @package = params[:package]

    object = Project.get_by_name(@project)
    object = Package.get_by_project_and_name(@project, @package, use_source: false, follow_project_links: false) if @package

    if request.get?

      @rating = object.rating(User.session!.id)
      return

    elsif request.put?

      # try to get previous rating of this user for this object
      previous_rating = Rating.where('object_type=? AND object_id=? AND user_id=?', object.class.name, object.id, User.session!.id).first
      data = Xmlhash.parse(request.raw_post)
      if previous_rating
        # update previous rating
        previous_rating.score = data.to_i
        previous_rating.save
      else
        # create new rating entry
        begin
          rating = Rating.new
          rating.score = data.to_i
          rating.object_type = object.class.name
          rating.object_id = object.id
          rating.user_id = User.session!.id
          rating.save
        rescue StandardError
          render_error status: 400, errorcode: 'error setting rating',
                       message: 'rating not saved'
          return
        end
      end
      render_ok
      return
    end

    render_error status: 400, errorcode: 'invalid_method',
                 message: 'only GET or PUT method allowed for this action'
  end

  def download_counter
    # FIXME: download stats are currently not supported and needs a re-implementation
    render_error status: 400, errorcode: 'not_supported', message: 'download stats need a re-implementation'
  end

  def newest_stats
    render_error status: 400, errorcode: 'not_supported', message: 'download stats need a re-implementation'
  end

  def most_active_projects
    # get all packages including activity values
    @packages = Package.select("packages.*, #{Package.activity_algorithm}")
                       .limit(@limit).order('activity_value DESC')
    # count packages per project and sum up activity values
    projects = {}
    @packages.each do |package|
      pro = package.project.name
      projects[pro] ||= { count: 0, activity: 0 }
      projects[pro][:count] += 1
      av = package.activity_value.to_f
      projects[pro][:activity] = av if av > projects[pro][:activity]
    end

    # sort by activity
    @projects = projects.sort do |a, b|
      b[1][:activity] <=> a[1][:activity]
    end

    @projects
  end

  def most_active_packages
    # get all packages including activity values
    @packages = Package.select("packages.*, #{Package.activity_algorithm}")
                       .limit(@limit).order('activity_value DESC')
    @packages
  end

  # FIXME3.0: remove route - activity is a completely useless value and only stored for sorting
  def activity
    @project = Project.get_by_name(params[:project])
    @package = Package.get_by_project_and_name(params[:project], params[:package], use_source: false, follow_project_links: false) if params[:package]
  end

  def latest_added
    packages = Package.limit(@limit).order('created_at DESC, name').to_a
    projects = Project.limit(@limit).order('created_at DESC, name').to_a

    list = projects
    list.concat(packages)
    list.sort! { |a, b| b.created_at <=> a.created_at }

    @list = if @limit
              list[0..@limit - 1]
            else
              list
            end
  end

  def added_timestamp
    @project = Project.get_by_name(params[:project])
    @package = Package.get_by_project_and_name(params[:project], params[:package], use_source: false, follow_project_links: true)

    # is it used at all ?
  end

  def latest_updated
    prj_filter = params[:prjfilter]
    pkg_filter = params[:pkgfilter]

    if params[:timelimit].nil?
      @timelimit = nil
    else
      @timelimit = params[:timelimit].to_i.day.ago
      # Override the default, since we want to limit by the time here.
      @limit = nil if params[:limit].nil?
    end

    @list = StatisticsCalculations.get_latest_updated(@limit, @timelimit, prj_filter, pkg_filter)
  end

  def updated_timestamp
    @project = Project.get_by_name(params[:project])
    @package = Package.get_by_project_and_name(params[:project], params[:package], use_source: false, follow_project_links: true)
  end

  def global_counters
    @users = User.count
    @repos = Repository.count
    @projects = Project.count
    @packages = Package.count
  end

  def get_limit
    return @limit = nil if !params[:limit].nil? && params[:limit].to_i.zero?

    @limit = 10 if (@limit = params[:limit].to_i).zero?
  end

  def active_request_creators
    required_parameters :project

    # get the devel projects
    @project = Project.find_by_name!(params[:project])

    # get devel projects
    ids = Package.joins('left outer join packages d on d.develpackage_id = packages.id')
                 .where('d.project_id' => @project.id).distinct.order('packages.project_id').pluck('packages.project_id')
    ids << @project.id
    projects = Project.where(id: ids).pluck(:name)

    # get all requests to it
    actions = BsRequestAction.where(target_project: projects).select(:bs_request_id)
    reqs = BsRequest.where(id: actions).select([:id, :created_at, :creator])
    if params[:raw] == '1'
      render json: reqs
      return
    end
    reqs = reqs.group_by { |r| r.created_at.strftime('%Y-%m') }
    @stats = []
    reqs.sort.each do |month, requests|
      monstats = []
      requests.group_by(&:creator).sort.each do |creator, list|
        monstats << [creator, User.find_by_login(creator).email, list.length]
      end
      @stats << [month, monstats]
    end
    respond_to do |format|
      format.xml
      format.json { render json: @stats }
    end
  end
end
