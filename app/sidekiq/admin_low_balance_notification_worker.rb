# frozen_string_literal: true

# TODO (ershad): Remove this worker after https://github.com/gumroad/gumroad/pull/28122 is
# merged and deployed to production.
class AdminLowBalanceNotificationWorker
  include Sidekiq::Job
  sidekiq_options retry: 5, queue: :default

  LOW_BALANCE_NOTIFICATION_THRESHOLD_CENTS = -100_00

  def perform(purchase_id)
    user = Purchase.find(purchase_id).seller

    if user.unpaid_balance_cents <= LOW_BALANCE_NOTIFICATION_THRESHOLD_CENTS
      AdminMailer.low_balance_notify(user.id, purchase_id).deliver_now
    end
  end
end
