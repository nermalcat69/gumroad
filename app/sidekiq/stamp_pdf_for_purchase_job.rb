# frozen_string_literal: true

# Stamps PDF(s) for a purchase
class StampPdfForPurchaseJob
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5, lock: :until_executed

  def perform(purchase_id)
    if Feature.active?(:skip_pdf_stamping)
      # Log the purchase_id to a Redis array
      $redis.rpush("stamp_pdf_purchase_ids", purchase_id)

      # Skip the job processing
      return
    end

    purchase = Purchase.find(purchase_id)
    PdfStampingService.stamp_for_purchase!(purchase)
  rescue PdfStampingService::Error => e
    Rails.logger.error("[#{self.class.name}.#{__method__}] Failed stamping for purchase #{purchase.id}: #{e.message}")
  end
end
