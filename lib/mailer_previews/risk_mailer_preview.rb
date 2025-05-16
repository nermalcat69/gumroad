# frozen_string_literal: true

class RiskMailerPreview < ActionMailer::Preview
  def suspend_user_for_tos_violation
    RiskMailer.suspend_user_for_tos_violation(User.last.id)
  end

  def user_flagged_for_fraud
    RiskMailer.user_flagged_for_fraud(User.last.id)
  end

  def probation_with_reminder
    RiskMailer.probation_with_reminder(User.last.id, User::Risk::PROBATION_WITH_REMINDER_DAYS)
  end

  def probation_review
    RiskMailer.probation_review(User.last.id)
  end

  def user_flagged_for_tos_violation
    link = Link.last
    RiskMailer.user_flagged_for_tos_violation("test@gumroad.com", Compliance::TOS_VIOLATION_REASONS.values.sample, link.user.id, link.id)
  end

  def user_suspended_for_fraud
    RiskMailer.user_suspended_for_fraud(User.last.id)
  end

  def user_suspension_for_fraud_notification
    RiskMailer.user_suspension_for_fraud_notification(User.last.id)
  end

  def user_suspension_for_tos_violation_notification
    RiskMailer.user_suspension_for_tos_violation_notification(User.last.id)
  end
end
