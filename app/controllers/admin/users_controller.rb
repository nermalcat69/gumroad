# frozen_string_literal: true

class Admin::UsersController < Admin::BaseController
  include Pagy::Backend

  skip_before_action :require_admin!, if: :request_from_iffy?, only: %i[suspend_for_fraud_from_iffy mark_compliant_from_iffy flag_for_explicit_nsfw_tos_violation_from_iffy]
  before_action :fetch_user

  helper Pagy::UrlHelpers

  PRODUCTS_ORDER = "ISNULL(COALESCE(purchase_disabled_at, banned_at, links.deleted_at)) DESC, created_at DESC"
  PRODUCTS_PER_PAGE = 10

  def show
    @title = "#{@user.display_name} on Gumroad"
    @pagy, @products = pagy(@user.links.order(Arel.sql(PRODUCTS_ORDER)), limit: PRODUCTS_PER_PAGE)
    respond_to do |format|
      format.html
      format.json { render json: @user }
    end
  end

  def stats
    render partial: "stats", locals: { user: @user }
  end

  def mark_compliant
    @user.mark_compliant!(author_id: current_user.id)
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def mark_compliant_from_iffy
    @user.mark_compliant!(author_name: "iffy")
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def suspend_for_fraud
    unless @user.suspended?
      @user.suspend_for_fraud!(author_id: current_user.id)
      suspension_note = params.dig(:suspend_for_fraud, :suspension_note).presence
      if suspension_note
        @user.comments.create!(
          author_id: current_user.id,
          author_name: current_user.name,
          comment_type: Comment::COMMENT_TYPE_SUSPENSION_NOTE,
          content: suspension_note
        )
      end
    end
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def suspend_for_fraud_from_iffy
    @user.flag_for_fraud!(author_name: "iffy") unless @user.flagged_for_fraud? || @user.on_probation? || @user.suspended?
    @user.suspend_for_fraud!(author_name: "iffy") unless @user.suspended?
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def flag_for_explicit_nsfw_tos_violation_from_iffy
    @user.flag_for_explicit_nsfw_tos_violation!(author_name: "iffy") unless @user.flagged_for_explicit_nsfw?
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def flag_for_fraud
    if !@user.flagged_for_fraud? && !@user.suspended_for_fraud?
      @user.flag_for_fraud!(author_id: current_user.id)
      flag_note = params.dig(:flag_for_fraud, :flag_note).presence
      if flag_note
        @user.comments.create!(
          author_id: current_user.id,
          author_name: current_user.name,
          comment_type: Comment::COMMENT_TYPE_FLAG_NOTE,
          content: flag_note
        )
      end
    end
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def put_on_probation
    content = "Probated (payouts suspended) manually by #{current_user.name_or_username} on #{Time.current.to_fs(:formatted_date_full_month)}"
    @user.put_on_probation!(author_id: current_user.id, content:) unless @user.on_probation?
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def probation_with_reminder
    @user.put_on_probation_with_reminder!(current_user.id, params[:days].to_i) unless @user.on_probation?
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def suspend_for_tos_violation
    @user.suspend_for_tos_violation!(author_id: current_user.id) unless @user.suspended?
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def verify
    @user.verified = !@user.verified
    @user.save!
    render json: { success: true }
  rescue => e
    render json: { success: false, message: e.message }
  end

  def refund_balance
    RefundUnpaidPurchasesWorker.perform_async(@user.id, current_user.id)
    render json: { success: true }
  end

  private
    def fetch_user
      if params[:id].include?("@")
        @user = User.find_by(email: params[:id])
      else
        @user = User.find_by(username: params[:id]) ||
                User.find_by(id: params[:id])
      end

      e404 unless @user
    end
end
