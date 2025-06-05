require "spec_helper"

RSpec.describe ReportMailer do
  describe "ytd_sales_report" do
    let(:csv_data) { "country,state,sales\nUSA,CA,100\nUSA,NY,200" }
    let(:recipient_email) { "test@example.com" }
    let(:mail) { ReportMailer.ytd_sales_report(csv_data, recipient_email) }

    it "sends the email to the correct recipient" do
      expect(mail.to).to eq([recipient_email])
    end

    it "has the correct subject" do
      expect(mail.subject).to eq("Year-to-Date Sales Report by Country/State")
    end

    it "has the correct body" do
      expect(mail.body.encoded).to include("Hello, the report is attached.")
    end

    it "has the correct content type" do
      expect(mail.content_type).to start_with("text/html")
    end

    it "attaches the CSV file" do
      expect(mail.attachments.length).to eq(1)
      attachment = mail.attachments[0]
      expect(attachment.filename).to eq("ytd_sales_by_country_state.csv")
      expect(attachment.content_type).to eq("text/csv; filename=ytd_sales_by_country_state.csv")
      expect(Base64.decode64(attachment.body.encoded)).to eq(csv_data)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq([ApplicationMailer::NOREPLY_EMAIL])
    end
  end
end
