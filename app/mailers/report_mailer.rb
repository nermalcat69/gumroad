class ReportMailer < ApplicationMailer
  def ytd_sales_report(csv_data, recipient_email)
    attachments["ytd_sales_by_country_state.csv"] = {
      mime_type: 'text/csv',
      content: csv_data
    }
    mail(to: recipient_email, subject: "Year-to-Date Sales Report by Country/State")
  end
end
