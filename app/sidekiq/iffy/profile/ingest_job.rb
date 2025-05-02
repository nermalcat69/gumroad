# frozen_string_literal: true

class Iffy::Profile::IngestJob
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  def perform(user_id)
    if Feature.active?(:skip_iffy_profile_ingest)
      $redis.rpush("iffy_profile_ingest_job_ids", user_id)
      return
    end

    user = User.find(user_id)

    Iffy::Profile::IngestService.new(user).perform
  end
end
