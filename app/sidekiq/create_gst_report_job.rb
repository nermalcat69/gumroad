# frozen_string_literal: true

class CreateGstReportJob
  include Sidekiq::Job
  sidekiq_options retry: 1, queue: :default, lock: :until_executed, on_conflict: :replace

  def perform(country_code, currency, quarter, year)
    raise ArgumentError, "Invalid quarter" unless quarter.in?(1..4)
    raise ArgumentError, "Invalid year" unless year.in?(2014..3200)

    s3_report_key = "sales-tax/#{country_code.downcase}-gst-quarterly/#{country_code.downcase}-gst-report-Q#{quarter}-#{year}-#{SecureRandom.hex(4)}.csv"

    row_headers = ["Member Country of Consumption", "GST rate in Member Country",
                   "Total value of supplies excluding GST (USD)",
                   "Total value of supplies excluding GST (Estimated, USD)",
                   "GST amount due (USD)",
                   "Total value of supplies excluding GST (#{currency})",
                   "Total value of supplies excluding GST (Estimated, #{currency})",
                   "GST amount due (#{currency})"]

    begin
      temp_file = Tempfile.new
      temp_file.write(row_headers.to_csv)

      ZipTaxRate.where(country: country_code, state: nil, user_id: nil).each do |zip_tax_rate|
        next unless zip_tax_rate.combined_rate > 0

        total_excluding_gst_cents = 0
        total_gst_cents = 0
        total_excluding_gst_cents_estimated = 0
        total_excluding_gst_cents_in_currency = 0
        total_gst_cents_in_currency = 0
        total_excluding_gst_cents_estimated_in_currency = 0

        start_date_of_quarter = Date.new(year, (1 + 3 * (quarter - 1)).to_i).beginning_of_month
        end_date_of_quarter = Date.new(year, (3 + 3 * (quarter - 1)).to_i).end_of_month

        (start_date_of_quarter..end_date_of_quarter).each do |date|
          conversion_rate = usd_rate_for_date(currency, date)

          gst_purchases_in_period = zip_tax_rate.purchases
                                        .where("purchase_state != 'failed'")
                                        .where("stripe_transaction_id IS NOT NULL")
                                        .not_chargedback
                                        .where(created_at: date.beginning_of_day..date.end_of_day)

          gst_chargeback_won_purchases_in_period = zip_tax_rate.purchases
                                                       .where("purchase_state != 'failed'")
                                                       .chargedback
                                                       .where("flags & :bit = :bit", bit: Purchase.flag_mapping["flags"][:chargeback_reversed])
                                                       .where(created_at: date.beginning_of_day..date.end_of_day)

          gst_refunds_in_period = zip_tax_rate.purchases
                                      .where("purchase_state != 'failed'")
                                      .joins(:refunds)
                                      .where(created_at: date.beginning_of_day..date.end_of_day)

          purchase_excluding_gst_amount_cents_in_period = gst_purchases_in_period.sum(:price_cents)
          purchase_gst_cents_in_period = gst_purchases_in_period.sum(:gumroad_tax_cents)

          purchase_excluding_gst_amount_cents_in_period += gst_chargeback_won_purchases_in_period.sum(:price_cents)
          purchase_gst_cents_in_period += gst_chargeback_won_purchases_in_period.sum(:gumroad_tax_cents)

          refund_excluding_gst_amount_cents_in_period = nil
          refund_gst_cents_in_period = nil
          timeout_seconds = ($redis.get(RedisKey.create_gst_report_job_max_execution_time_seconds) || 1.hour).to_i
          WithMaxExecutionTime.timeout_queries(seconds: timeout_seconds) do
            refund_excluding_gst_amount_cents_in_period = gst_refunds_in_period.sum("refunds.amount_cents")
            refund_gst_cents_in_period = gst_refunds_in_period.sum("refunds.gumroad_tax_cents")
          end

          total_excluding_gst_cents += purchase_excluding_gst_amount_cents_in_period - refund_excluding_gst_amount_cents_in_period
          total_excluding_gst_cents_estimated += (purchase_gst_cents_in_period - refund_gst_cents_in_period) / zip_tax_rate.combined_rate
          total_gst_cents += purchase_gst_cents_in_period - refund_gst_cents_in_period

          total_excluding_gst_cents_in_currency += (purchase_excluding_gst_amount_cents_in_period - refund_excluding_gst_amount_cents_in_period) / conversion_rate
          total_excluding_gst_cents_estimated_in_currency += ((purchase_gst_cents_in_period - refund_gst_cents_in_period) / zip_tax_rate.combined_rate) / conversion_rate
          total_gst_cents_in_currency += (purchase_gst_cents_in_period - refund_gst_cents_in_period) / conversion_rate
        end

        temp_file.write([ISO3166::Country[zip_tax_rate.country].common_name,
                         zip_tax_rate.combined_rate * 100,
                         Money.new(total_excluding_gst_cents, :usd).format(no_cents_if_whole: false, symbol: false),
                         Money.new(total_excluding_gst_cents_estimated, :usd).format(no_cents_if_whole: false, symbol: false),
                         Money.new(total_gst_cents, :usd).format(no_cents_if_whole: false, symbol: false),
                         Money.new(total_excluding_gst_cents_in_currency, currency.downcase.to_sym).format(no_cents_if_whole: false, symbol: false),
                         Money.new(total_excluding_gst_cents_estimated_in_currency, currency.downcase.to_sym).format(no_cents_if_whole: false, symbol: false),
                         Money.new(total_gst_cents_in_currency, currency.downcase.to_sym).format(no_cents_if_whole: false, symbol: false)].to_csv)
        temp_file.flush
      end
      temp_file.rewind
      s3_object = Aws::S3::Resource.new.bucket(REPORTING_S3_BUCKET).object(s3_report_key)
      s3_object.upload_file(temp_file)
      s3_signed_url = s3_object.presigned_url(:get, expires_in: 1.week.to_i).to_s

      AdminMailer.gst_report(country_code, quarter, year, s3_signed_url).deliver_now
      SlackMessageWorker.perform_async("payments", "#{ISO3166::Country[country_code].common_name} GST Reporting", "Q#{quarter} #{year} #{ISO3166::Country[country_code].common_name} GST report is ready - #{s3_signed_url}", "green")
    ensure
      temp_file.close
    end
  end

  private
    def usd_rate_for_date(currency, date)
      formatted_date = date.strftime("%Y-%m-%d")
      api_url =
          "#{OPEN_EXCHANGE_RATES_API_BASE_URL}/historical/#{formatted_date}.json?app_id=#{OPEN_EXCHANGE_RATE_KEY}&base=#{currency}"

      JSON.parse(URI.open(api_url).read)["rates"]["USD"]
    end
end
