class Webui::GroupsController < Webui::WebuiController
  before_action :require_login, except: [:show, :autocomplete]
  before_action :set_group, only: :show
  after_action :verify_authorized, except: [:show, :autocomplete]

  def index
    authorize Group, :index?
    @groups = Group.all.includes(:users)
  end

  def show; end

  def new
    authorize Group, :create?
  end

  def create
    authorize Group, :create?

    group = Group.new(title: group_params[:title])
    if group.save && group.replace_members(group_params[:members])
      flash[:success] = "Group '#{group}' successfully created."
      redirect_to controller: :groups, action: :index
    else
      redirect_back(fallback_location: root_path, error: "Group can't be saved: #{group.errors.full_messages.to_sentence}")
    end
  end

  def autocomplete
    groups = Group.where('title LIKE ?', "#{params[:term]}%").pluck(:title) if params[:term]
    render json: groups || []
  end

  private

  def group_params
    params.require(:group).permit(:title, :members)
  end

  def set_group
    @group = Group.find_by_title(params[:title])

    # Group.find_by_title! is self implemented and would raise an 500 error
    return if @group

    flash[:error] = "Group '#{params[:title]}' does not exist"
    redirect_back(fallback_location: { controller: 'main', action: 'index' })
  end
end
