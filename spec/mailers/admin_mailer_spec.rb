# frozen_string_literal: true

require "spec_helper"

describe AdminMailer do
  describe "#chargeback_notify" do
    context "for a dispute on Purchase" do
      let!(:purchase) { create(:purchase) }
      let!(:dispute) { create(:dispute_formalized, purchase:) }
      let!(:mail) { described_class.chargeback_notify(dispute.id) }

      it "emails payments" do
        expect(mail.to).to eq [ApplicationMailer::RISK_EMAIL]
      end

      it "has the id of the seller" do
        expect(mail.body).to include(dispute.disputable.seller.id)
      end

      it "has the details of the purchase" do
        expect(mail.subject).to eq "[test] Chargeback for #{purchase.formatted_disputed_amount} on #{purchase.link.name}"
        expect(mail.body.encoded).to include purchase.link.name
        expect(mail.body.encoded).to include purchase.formatted_disputed_amount
      end
    end

    context "for a dispute on Charge", :vcr do
      let!(:charge) do
        charge = create(:charge, seller: create(:user), amount_cents: 15_00)
        charge.purchases << create(:purchase, link: create(:product, user: charge.seller), total_transaction_cents: 2_50)
        charge.purchases << create(:purchase, link: create(:product, user: charge.seller), total_transaction_cents: 5_00)
        charge.purchases << create(:purchase, link: create(:product, user: charge.seller), total_transaction_cents: 7_50)
        charge
      end
      let!(:dispute) { create(:dispute_formalized_on_charge, purchase: nil, charge:) }
      let!(:mail) { described_class.chargeback_notify(dispute.id) }

      it "emails payments" do
        expect(mail.to).to eq [ApplicationMailer::RISK_EMAIL]
      end

      it "has the id of the seller" do
        expect(mail.body).to include(dispute.disputable.seller.id)
      end

      it "has the details of all included purchases" do
        selected_purchase = charge.purchase_for_dispute_evidence
        expect(mail.subject).to eq "[test] Chargeback for #{charge.formatted_disputed_amount} on #{selected_purchase.link.name} and 2 other products"
        charge.disputed_purchases.each do |purchase|
          expect(mail.body.encoded).to include purchase.external_id
          expect(mail.body.encoded).to include purchase.link.name
        end
      end
    end
  end

  describe "#low_balance_notify", :sidekiq_inline, :elasticsearch_wait_for_refresh do
    before do
      @user = create(:user, name: "Test Creator", unpaid_balance_cents: -600_00)

      @last_refunded_purchase = create(:purchase)
      @mail = AdminMailer.low_balance_notify(@user.id, @last_refunded_purchase.id)
    end

    it "has 'to' field set to risk@gumroad.com" do
      expect(@mail.to).to eq([ApplicationMailer::RISK_EMAIL])
    end

    it "has the correct subject" do
      expect(@mail.subject).to eq "[test] Low balance for creator - Test Creator ($-600)"
    end

    it "includes user balance in mail body" do
      expect(@mail.body).to include("Balance: $-600")
    end

    it "includes admin purchase link" do
      expect(@mail.body).to include(admin_purchase_url(@last_refunded_purchase))
    end

    it "includes admin product link" do
      expect(@mail.body).to include(admin_product_url(@last_refunded_purchase.link.unique_permalink))
    end
  end

  describe "#vat_report" do
    let(:dummy_s3_link) { "https://test_vat_link.at.s3" }

    before do
      @mail = AdminMailer.vat_report(3, 2015, dummy_s3_link)
    end

    it "has the s3 link in the body" do
      expect(@mail.body).to include("VAT report Link: #{dummy_s3_link}")
    end

    it "indicates the quarter and year of reporting period in the subject" do
      expect(@mail.subject).to eq("VAT report for Q3 2015")
    end

    it "is to team" do
      expect(@mail.to).to eq([ApplicationMailer::PAYMENTS_EMAIL])
    end
  end

  describe "#gst_report" do
    let(:dummy_s3_link) { "https://test_vat_link.at.s3" }

    before do
      @mail = AdminMailer.gst_report("AU", 3, 2015, dummy_s3_link)
    end

    it "contains the s3 link in the body" do
      expect(@mail.body).to include("GST report Link: #{dummy_s3_link}")
    end

    it "indicates the quarter and year of reporting period in the subject" do
      expect(@mail.subject).to eq("Australia GST report for Q3 2015")
    end

    it "sends to team" do
      expect(@mail.to).to eq([ApplicationMailer::PAYMENTS_EMAIL])
    end
  end

  describe "#funds_received_report" do
    it "sends and email" do
      last_month = Time.current.last_month
      email = AdminMailer.funds_received_report(last_month.month, last_month.year)
      expect(email.body.parts.size).to eq(2)
      expect(email.body.parts.collect(&:content_type)).to match_array(["text/html; charset=UTF-8", "text/csv; filename=funds-received-report-#{last_month.month}-#{last_month.year}.csv"])
      html_body = email.body.parts.find { |part| part.content_type.include?("html") }.body
      expect(html_body).to include("Funds Received Report")
      expect(html_body).to include("Sales")
      expect(html_body).to include("total_transaction_cents")
    end
  end

  describe "#deferred_refunds_report" do
    it "sends and email" do
      last_month = Time.current.last_month
      email = AdminMailer.deferred_refunds_report(last_month.month, last_month.year)
      expect(email.body.parts.size).to eq(2)
      expect(email.body.parts.collect(&:content_type)).to match_array(["text/html; charset=UTF-8", "text/csv; filename=deferred-refunds-report-#{last_month.month}-#{last_month.year}.csv"])
      html_body = email.body.parts.find { |part| part.content_type.include?("html") }.body
      expect(html_body).to include("Deferred Refunds Report")
      expect(html_body).to include("Sales")
      expect(html_body).to include("total_transaction_cents")
    end
  end
end
