# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  SUBJECT_PREFIX = ("[#{Rails.env}] " unless Rails.env.production?)

  default from: ADMIN_EMAIL
  default to: DEVELOPERS_EMAIL

  layout "layouts/email"

  def funds_received_report(month, year)
    WithMaxExecutionTime.timeout_queries(seconds: 1.hour) do
      @report = FundsReceivedReports.funds_received_report(month, year)
    end

    report_csv = AdminFundsCsvReportService.new(@report).generate
    attachments["funds-received-report-#{month}-#{year}.csv"] = { data: report_csv }
    mail subject: "#{SUBJECT_PREFIX}Funds Received Report – #{month}/#{year}",
         to: PAYMENTS_EMAIL,
         cc: %w[solson@earlygrowthfinancialservices.com ndelgado@earlygrowthfinancialservices.com chhabra.harbaksh@gmail.com]
  end

  def deferred_refunds_report(month, year)
    @report = DeferredRefundsReports.deferred_refunds_report(month, year)

    report_csv = AdminFundsCsvReportService.new(@report).generate
    attachments["deferred-refunds-report-#{month}-#{year}.csv"] = { data: report_csv }
    mail subject: "#{SUBJECT_PREFIX}Deferred Refunds Report – #{month}/#{year}",
         to: PAYMENTS_EMAIL,
         cc: %w[solson@earlygrowthfinancialservices.com ndelgado@earlygrowthfinancialservices.com chhabra.harbaksh@gmail.com]
  end

  def chargeback_notify(dispute_id)
    dispute = Dispute.find(dispute_id)
    @disputable = dispute.disputable
    @user = @disputable.seller

    subject = "#{SUBJECT_PREFIX}Chargeback for #{@disputable.formatted_disputed_amount} on #{@disputable.purchase_for_dispute_evidence.link.name}"
    subject += " and #{@disputable.disputed_purchases.count - 1} other products" if @disputable.multiple_purchases?

    mail subject:,
         to: RISK_EMAIL
  end

  def low_balance_notify(user_id, last_refunded_purchase_id)
    @user = User.find(user_id)
    @purchase = Purchase.find(last_refunded_purchase_id)
    @product = @purchase.link

    mail subject: "#{SUBJECT_PREFIX}Low balance for creator - #{@user.name} (#{@user.balance_formatted(via: :elasticsearch)})",
         to: RISK_EMAIL
  end

  def vat_report(vat_quarter, vat_year, s3_read_url)
    @subject_and_title = "VAT report for Q#{vat_quarter} #{vat_year}"
    @s3_url = s3_read_url

    mail subject: @subject_and_title,
         to: PAYMENTS_EMAIL,
         cc: %w[solson@earlygrowthfinancialservices.com chhabra.harbaksh@gmail.com]
  end

  def gst_report(country_code, quarter, year, s3_read_url)
    @country_name = ISO3166::Country[country_code].common_name
    @subject_and_title = "#{@country_name} GST report for Q#{quarter} #{year}"
    @s3_url = s3_read_url

    mail subject: @subject_and_title,
         to: PAYMENTS_EMAIL,
         cc: %w[solson@earlygrowthfinancialservices.com chhabra.harbaksh@gmail.com]
  end

  def payable_report(csv_url, year)
    @subject_and_title = "Payable report for year #{year} is ready to download"
    @csv_url = csv_url

    mail subject: @subject_and_title,
         to: %w[payments@gumroad.com chhabra.harbaksh@gmail.com]
  end
end
