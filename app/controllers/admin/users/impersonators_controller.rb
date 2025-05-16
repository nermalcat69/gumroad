# frozen_string_literal: true

class Admin::Users::ImpersonatorsController < Admin::BaseController
  skip_before_action :require_admin!, only: :destroy
  before_action :require_current_user_as_admin!, only: :destroy

  def create
    user = User.find(params[:user_id])
    authorize [:admin, :impersonators, user], :create?

    impersonate_user(user)
    redirect_to(dashboard_url, notice: "You are now impersonating #{user.display_name}!")
  end

  def destroy
    perviously_impersonated_user = impersonated_user
    stop_impersonating_user

    render json: { redirect_to: admin_user_url(perviously_impersonated_user) }
  end

  private
    def require_current_user_as_admin!
      if !user_signed_in? || !current_user.is_team_member?
        return e404_json if xhr_or_json_request?
        redirect_to root_url
      end
    end
end
