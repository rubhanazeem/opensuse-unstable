class MailHandlerController < ApplicationController
  skip_before_action :extract_user
  skip_before_action :require_login

  def upload
    # UNIMPLEMENTED STUB JUST FOR TESTING
    render_ok
  end
end
