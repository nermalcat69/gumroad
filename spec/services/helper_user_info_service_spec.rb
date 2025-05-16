# frozen_string_literal: true

require "spec_helper"

describe HelperUserInfoService do
  include Rails.application.routes.url_helpers

  let(:user) { create(:user, email: "user@example.com") }

  describe "#user_info" do
    let(:service) { described_class.new(email: user.email) }

    it "retrieves user info" do
      allow_any_instance_of(User).to receive(:sales_cents_total).and_return(2250)

      result = service.user_info
      expect(result[:prompt]).to include("User ID: #{user.id}")
      expect(result[:prompt]).to include("User Name: #{user.name}")
      expect(result[:prompt]).to include("User Email: #{user.email}")
      expect(result[:prompt]).to include("Account Status: Active")
      expect(result[:prompt]).to include("Total Earnings Since Joining: $22.50")
      expect(result[:metadata]).to eq({
                                        name: user.name,
                                        email: user.email,
                                        value: 2250,
                                        links: {
                                          "Impersonate": "http://app.test.gumroad.com:31337/admin/helper_actions/impersonate/#{user.external_id}"
                                        }
                                      })
    end

    context "value calculation" do
      let(:product) { create(:product, user:, price_cents: 100_00) }

      it "returns the higher value between lifetime sales and last-28-day purchases" do
        # Bought $10.00 of products in the last 28 days.
        create(:purchase, purchaser: user, price_cents: 10_00, created_at: 30.days.ago)
        create(:purchase, purchaser: user, price_cents: 10_00, created_at: 1.day.ago)
        index_model_records(Purchase)

        expect(service.user_info[:metadata][:value]).to eq(10_00)

        # Sold $100.00 of products, before fees.
        sale = create(:purchase, link: product, price_cents: 100_00, created_at: 30.days.ago)
        index_model_records(Purchase)

        expect(service.user_info[:metadata][:value]).to eq(sale.payment_cents)
      end
    end

    context "when user is not found" do
      let(:service) { described_class.new(email: "inexistent@example.com") }

      it "returns empty prompt and metadata" do
        result = service.user_info
        expect(result[:prompt]).to eq("")
        expect(result[:metadata]).to eq({})
      end
    end

    context "with recent purchase" do
      let(:service) { HelperUserInfoService.new(email: user.email) }

      it "includes recent purchase info" do
        product = create(:product)
        purchase = create(:purchase, purchaser: user, link: product, price_cents: 1_00, created_at: 1.day.ago)
        result = service.user_info

        expect(result[:prompt]).to include("Successful Purchase: #{purchase.email} bought #{product.name} for $1 on #{purchase.created_at.to_fs(:formatted_date_full_month)}")
        expect(result[:prompt]).to include("Product URL: #{product.long_url}")
        expect(result[:prompt]).to include("Creator Support Email: #{purchase.seller.support_email || purchase.seller.form_email}")
        expect(result[:prompt]).to include("Receipt URL: #{receipt_purchase_url(purchase.external_id, email: purchase.email, host: DOMAIN)}")
      end
    end

    context "when user has a Stripe Connect account" do
      it "includes the stripe_connect_account_id in links" do
        merchant_account = create(:merchant_account, charge_processor_id: StripeChargeProcessor.charge_processor_id)
        user_with_stripe = merchant_account.user
        service = described_class.new(email: user_with_stripe.email)

        result = service.user_info
        expect(result[:metadata][:links]["View Stripe account"]).to eq("http://app.test.gumroad.com:31337/admin/helper_actions/stripe_dashboard/#{user_with_stripe.external_id}")
      it "includes recent purchase" do
        purchase = create(:purchase, purchaser: user, link: create(:product), price_cents: 1_00, created_at: 1.day.ago)
        expect(service.user_info).to eq({
                                          user:,
                                          account_infos: [],
                                          purchase_infos: [
                                            "The email #{purchase.email} was used to purchase #{purchase.link.name} for $1 on #{purchase.created_at.to_fs(:formatted_date_full_month)}",
                                            "The URL of the product is #{purchase.link.long_url}",
                                            "The creator's support email address is #{purchase.seller.email}",
                                            "The URL of the purchase receipt is #{receipt_purchase_url(purchase.external_id, host: DOMAIN)}",
                                            "The internal admin URL of the purchase is #{admin_purchase_url(purchase.external_id, host: DOMAIN)}",
                                          ],
                                          recent_purchase: purchase,
                                        })
      end
    end
  end

  describe "#user_properties" do
    let(:user) { create(:user) }
    let(:service) { described_class.new(email: user.email) }

    context "when user is not found" do
      let(:service) { described_class.new(email: "inexistent@example.com") }

      context "when a purchase with the email is not found" do
        it "returns nil" do
          expect(service.user_properties).to eq(nil)
        end
      end

      context "when a purchase with the email is found" do
        it "returns properties with nil values except admin_purchases_url" do
          purchase = create(:purchase, email: "purchaser_but_not_user@example.com", link: create(:product))
          service = described_class.new(email: purchase.email)
          expect(service.user_properties).to eq(
            name: nil,
            user_id: nil,
            stripe_connect_account_id: nil,
            admin_purchases_url: admin_search_purchases_url(query: purchase.email, host: DOMAIN),
            last_28_days_sales_total: nil
          )
        end
      end
    end

    context "when user is found" do
      it "returns user properties" do
        expect(service.user_properties).to eq({
                                                name: user.name,
                                                user_id: user.id,
                                                stripe_connect_account_id: nil,
                                                admin_purchases_url: nil,
                                                last_28_days_sales_total: 0
                                              })
      end
    end

    context "when there's a failed purchase" do
      it "includes failed purchase info" do
        product = create(:product)
        failed_purchase = create(:purchase, purchase_state: "failed", purchaser: user, link: product, price_cents: 1_00, created_at: 1.day.ago)
        result = described_class.new(email: user.email).user_info
        expect(result[:prompt]).to include("Failed Purchase Attempt: #{failed_purchase.email} tried to buy #{product.name} for $1 on #{failed_purchase.created_at.to_fs(:formatted_date_full_month)}")
        expect(result[:prompt]).to include("Error: #{failed_purchase.formatted_error_code}")
      context "when user has a Stripe Connect account" do
        it "returns non nil stripe_connect_account_id" do
          merchant_account = create(:merchant_account, charge_processor_merchant_id: "acct_user1")
          user = merchant_account.user
          service = described_class.new(email: user.email)

          expect(service.user_properties).to eq({
                                                  name: user.name,
                                                  user_id: user.id,
                                                  stripe_connect_account_id: "acct_user1",
                                                  admin_purchases_url: nil,
                                                  last_28_days_sales_total: 0
                                                })
        end
      end

      context "when user has past purchases" do
        it "returns non nil admin_purchases_url" do
          create(:purchase, purchaser: user)
          expect(service.user_properties).to eq({
                                                  name: user.name,
                                                  user_id: user.id,
                                                  stripe_connect_account_id: nil,
                                                  admin_purchases_url: admin_search_purchases_url(query: user.email, host: DOMAIN),
                                                  last_28_days_sales_total: 0
                                                })
        end
      end
    end

    context "when purchase has a refund policy" do
      it "includes refund policy info" do
        product = create(:product)
        purchase = create(:purchase, purchaser: user, link: product, created_at: 1.day.ago)
        purchase.create_purchase_refund_policy!(
          title: "This is a product-level refund policy",
          fine_print: "This is the fine print of the refund policy."
        )
        result = described_class.new(email: user.email).user_info
        expect(result[:prompt]).to include("Refund Policy: This is the fine print of the refund policy.")
      end
    end

    context "when purchase has a license key" do
      it "includes license key info" do
        product = create(:product, is_licensed: true)
        purchase = create(:purchase, purchaser: user, link: product, created_at: 1.day.ago)
        license = create(:license, purchase: purchase)
        result = described_class.new(email: user.email).user_info
        expect(result[:prompt]).to include("License Key: #{license.serial}")
      end
    end
  end
end
