# frozen_string_literal: true

require "spec_helper"

describe CreateGstReportJob do
  it "raises an ArgumentError if the year is less than 2014 or greater than 3200" do
    expect do
      described_class.new.perform("AU", "AUD", 2, 2013, 1.50, 1.50, 1.50)
    end.to raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the quarter is not within 1 and 4 inclusive" do
    expect do
      described_class.new.perform("AU", "AUD", 0, 2013, 1.50, 1.50, 1.50)
    end.to raise_error(ArgumentError)

    expect do
      described_class.new.perform("AU", "AUD", 5, 2013, 1.50, 1.50, 1.50)
    end.to raise_error(ArgumentError)
  end

  describe "happy case", :vcr do
    let(:s3_bucket_double) do
      s3_bucket_double = double
      allow(Aws::S3::Resource).to receive_message_chain(:new, :bucket).and_return(s3_bucket_double)
      s3_bucket_double
    end

    before :context do
      @s3_object = Aws::S3::Resource.new.bucket("gumroad-specs").object("specs/au-gst-reporting-spec-#{SecureRandom.hex(18)}.zip")
    end

    before do
      create(:zip_tax_rate, country: "AU", state: nil, zip_code: nil, combined_rate: 0.10, flags: 0)

      q1_time = Time.zone.local(2015, 1, 1)
      q1_m2_time = Time.zone.local(2015, 2, 1)
      q2_time = Time.zone.local(2015, 5, 1)

      product = create(:product, price_cents: 200_00)

      travel_to(q1_time) do
        purchase1 = create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                                      perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia")
        purchase1.process!

        purchase2 = create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                                      perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia")
        purchase2.process!
        purchase2.refund_gumroad_taxes!(refunding_user_id: 1)

        purchase3 = create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                                      perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia")
        purchase3.process!

        purchase1.chargeback_date = Time.current
        purchase1.chargeback_reversed = true
        purchase1.save!
      end

      travel_to(q1_m2_time) do
        purchase1 = create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                                      perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia")
        purchase1.process!

        purchase2 = create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                                      perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia")
        purchase2.process!

        purchase2_refund_flow_of_funds = FlowOfFunds.build_simple_flow_of_funds(Currency::USD, purchase2.gross_amount_refundable_cents)
        purchase2.refund_purchase!(purchase2_refund_flow_of_funds, nil)
      end

      travel_to(q2_time) do
        create(:purchase, link: product, chargeable: build(:chargeable), quantity: 1,
                          perceived_price_cents: 200_00, country: "Australia", ip_country: "Australia").process!
      end
    end

    it "returns a csv file for the quarter" do
      expect(s3_bucket_double).to receive(:object).and_return(@s3_object)
      expect(AdminMailer).to receive(:gst_report).with("AU", 1, 2015, anything).and_call_original

      described_class.new.perform("AU", "AUD", 1, 2015)

      expect(SlackMessageWorker).to have_enqueued_sidekiq_job("payments", "Australia GST Reporting", anything, "green")

      report_verification_helper
    end

    def report_verification_helper
      temp_file = Tempfile.new("actual-file", encoding: "ascii-8bit")

      @s3_object.get(response_target: temp_file)
      temp_file.rewind
      actual_payload = CSV.read(temp_file)

      expect(actual_payload[0]).to eq(["Member Country of Consumption", "GST rate in Member Country",
                                       "Total value of supplies excluding GST (USD)",
                                       "Total value of supplies excluding GST (Estimated, USD)",
                                       "GST amount due (USD)",
                                       "Total value of supplies excluding GST (AUD)",
                                       "Total value of supplies excluding GST (Estimated, AUD)",
                                       "GST amount due (AUD)"])
      expect(actual_payload[1]).to eq(["Australia", "10.0", "800.00", "600.00", "60.00", "994.19", "748.61", "74.86"])
    ensure
      temp_file.close(true)
    end
  end
end
