# frozen_string_literal: true

class Iffy::Product::IngestJob
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  def perform(product_id)
    if Feature.active?(:skip_iffy_product_ingest)
      $redis.rpush("iffy_product_ingest_job_ids", product_id)
      return
    end

    product = Link.find(product_id)

    Iffy::Product::IngestService.new(product).perform
  end
end
