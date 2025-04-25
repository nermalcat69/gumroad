# frozen_string_literal: true

class AdminMailerPreview < ActionMailer::Preview
  def chargeback_notify
    AdminMailer.chargeback_notify(Purchase.last.id)
  end

  def funds_received_report
    last_month = Time.current.last_month
    AdminMailer.funds_received_report(last_month.month, last_month.year)
  end

  def deferred_refunds_report
    last_month = Time.current.last_month
    AdminMailer.deferred_refunds_report(last_month.month, last_month.year)
  end

  def gst_report
    AdminMailer.gst_report("AU", 3, 2015, "http://www.gumroad.com")
  end

  def payable_report
    AdminMailer.payable_report("http://www.gumroad.com", 2019)
  end
end
