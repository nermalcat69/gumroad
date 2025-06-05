class ReportMailer < ApplicationMailer
  def ytd_sales_report(csv_data, recipient_email)
    attachments["ytd_sales_by_country_state.csv"] = {
      data: ::Base64.encode64(csv_data),
      encoding: 'base64'
    }
    mail(to: recipient_email, subject: "Year-to-Date Sales Report by Country/State", body: "Hello, the report is attached.", content_type: "text/html")
  end
end
