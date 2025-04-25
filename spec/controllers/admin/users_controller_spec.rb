# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::UsersController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  before do
    @admin_user = create(:admin_user, has_payout_privilege: true, has_risk_privilege: true)
    sign_in @admin_user
  end

  describe "POST events" do
    before do
      @user = create(:user)
      @product = create(:product, user_id: @user.id)
      @purchase = create(:purchase, link: @product, seller: @product.user, stripe_transaction_id: rand(9_999))
      @params = { id: @user.id }
    end

    describe "POST flag_for_fraud events" do
      it "successfully flags users for fraud and does not refund the purchases" do
        post :flag_for_fraud, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.flagged_for_fraud?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "successfully flags users for fraud with a flag note" do
        post :flag_for_fraud, params: @params.merge({ "flag_for_fraud[flag_note]": "This is a flag note" })
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.flagged_for_fraud?).to be(true)
        expect(@user.comments.where(comment_type: "flag_note").last.content).to eq("This is a flag note")
      end

      it "does not flag user for fraud if already flagged" do
        @user.flag_for_fraud(author_name: "test_author")
        post :flag_for_fraud, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.flagged_for_fraud?).to be(true)
      end
    end

    describe "POST put_on_probation" do
      it "probates the user and adds a comment" do
        post :put_on_probation, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.on_probation?).to be(true)
        expect(@user.comments.last.content).to eq("Probated (payouts suspended) manually by #{@admin_user.name_or_username} on #{Time.current.to_fs(:formatted_date_full_month)}")
      end
    end

    describe "POST suspend_for_fraud_from_iffy" do
      it "suspends users for fraud if they have not been flagged, and does not refund the purchases" do
        post :suspend_for_fraud_from_iffy, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_fraud?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "suspends users for fraud if they have been flagged, and does not refund the purchases" do
        post :flag_for_fraud, params: @params
        post :suspend_for_fraud_from_iffy, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_fraud?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "suspends users for fraud if they have been probated, and does not refund the purchases" do
        post :put_on_probation, params: @params
        post :suspend_for_fraud_from_iffy, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_fraud?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "logs out the user from all active sessions" do
        travel_to(DateTime.current) do
          expect do
            post :suspend_for_fraud_from_iffy, params: @params
          end.to change { @user.reload.last_active_sessions_invalidated_at }.from(nil).to(DateTime.current)
        end
      end

      context "when error is raised" do
        before do
          allow_any_instance_of(User).to receive(:flag_for_fraud!).and_raise("Error!")
        end

        it "rescues and returns error message" do
          post :suspend_for_fraud_from_iffy, params: @params

          expect(response.parsed_body["success"]).to be(false)
          expect(response.parsed_body["message"]).to eq("Error!")
        end
      end
    end

    describe "POST suspend_for_fraud events" do
      it "does not suspend seller for fraud if they have not been flagged, and does not refund the purchases" do
        post :suspend_for_fraud, params: @params

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq('Cannot transition user_risk_state via :suspend_for_fraud from :not_reviewed (Reason(s): User risk state cannot transition via "suspend for fraud")')
        expect(@user.reload.suspended_for_fraud?).to be(false)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "successfully suspends users for fraud if they have been flagged, and does not refund the purchases" do
        post :flag_for_fraud, params: @params
        post :suspend_for_fraud, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_fraud?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "successfully suspends users for fraud with a suspension note" do
        post :flag_for_fraud, params: @params
        post :suspend_for_fraud, params: @params.merge({ "suspend_for_fraud[suspension_note]": "This is a suspension note" })
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_fraud?).to be(true)
        expect(@user.comments.where(comment_type: "suspension_note").last.content).to eq("This is a suspension note")
      end
    end

    describe "POST probation_with_reminder" do
      let(:days) { User::Risk::PROBATION_WITH_REMINDER_DAYS }

      it "successfully puts the user on probation and schedules a reminder for review" do
        expect do
          @params = { id: @user.id, days: }
          post :probation_with_reminder, params: @params

          expect(response.parsed_body["success"]).to be(true)
          expect(@user.reload.on_probation?).to be(true)
          expect(ProbationReviewEmailWorker).to have_enqueued_sidekiq_job(@user.id)
        end.to have_enqueued_mail(RiskMailer, :probation_with_reminder).once.with(@user.id, days)
      end

      context "when error is raised" do
        before do
          allow_any_instance_of(User).to receive(:put_on_probation_with_reminder!).and_raise("Error!")
        end

        it "rescues and returns error message" do
          @params = { id: @user.id, days: }
          post :probation_with_reminder, params: @params

          expect(response.parsed_body["success"]).to be(false)
          expect(response.parsed_body["message"]).to eq("Error!")
        end
      end
    end

    describe "POST suspend_for_tos_violation" do
      it "does not suspend seller for TOS violation if they have not been flagged, and does not refund the purchases" do
        post :suspend_for_tos_violation, params: @params

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq('Cannot transition user_risk_state via :suspend_for_tos_violation from :not_reviewed (Reason(s): User risk state cannot transition via "suspend for tos violation")')
        expect(@user.reload.suspended_for_fraud?).to be(false)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end

      it "suspends users for TOS violations if they have been flagged, and does not refund the purchases" do
        @user.flag_for_tos_violation(author_name: "test_author", product_id: @product.id)
        post :suspend_for_tos_violation, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(@user.reload.suspended_for_tos_violation?).to be(true)
        expect(@purchase.reload.stripe_refunded).to be(nil)
      end
    end
  end

  describe "GET 'verify'" do
    before do
      @user = create(:user)
      @product = create(:product, user: @user)
      @purchases = []
      5.times do
        @purchases << create(:purchase, link: @product, seller: @product.user, stripe_transaction_id: rand(9_999))
      end
      @params = { id: @user.id }
    end

    it "successfully verifies and unverifies users" do
      expect(@user.verified.nil?).to be(true)
      get :verify, params: @params
      expect(response.parsed_body["success"]).to be(true)
      expect(@user.reload.verified).to be(true)

      get :verify, params: @params
      expect(response.parsed_body["success"]).to be(true)
      expect(@user.reload.verified).to be(false)
    end

    context "when error is raised" do
      before do
        allow_any_instance_of(User).to receive(:save!).and_raise("Error!")
      end

      it "rescues and returns error message" do
        get :verify, params: @params

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq("Error!")
      end
    end
  end

  describe "GET 'show'" do
    let(:user) { create(:user) }

    it "returns page successfully" do
      get "show", params: { id: user.id }
      expect(response.body).to have_text(user.name)
    end

    it "returns page successfully when using email" do
      get "show", params: { id: user.email }
      expect(response.body).to have_text(user.name)
    end

    it "handles user with 1 product" do
      product = create(:product, user:)

      get :show, params: { id: user.id }

      expect(response.body).to have_text(product.name)
      expect(response.body).not_to have_selector("[aria-label='Pagination']")
    end

    it "handles user with more than PRODUCTS_PER_PAGE" do
      products = []
      # result is ordered by created_at desc
      created_at = Time.zone.now
      20.times do |i|
        products << create(:product, user:, name: ("a".."z").to_a[i] * 10, created_at:)
        created_at -= 1
      end

      get :show, params: { page: 1, id: user.id }

      products.first(10).each do |product|
        expect(response.body).to have_text(product.name)
      end
      products.last(10).each do |product|
        expect(response.body).not_to have_text(product.name)
      end
      expect(response.body).to have_selector("[aria-label='Pagination']")

      get :show, params: { page: 2, id: user.id }

      products.first(10).each do |product|
        expect(response.body).not_to have_text(product.name)
      end
      products.last(10).each do |product|
        expect(response.body).to have_text(product.name)
      end
      expect(response.body).to have_selector("[aria-label='Pagination']")
    end

    describe "blocked email tooltip" do
      let(:email) { "john@example.com" }
      let!(:email_blocked_object) { BlockedObject.block!(:email, email, user) }
      let!(:email_domain_blocked_object) { BlockedObject.block!(:email_domain, Mail::Address.new(email).domain, user) }

      before do
        user.update!(email:)
      end

      it "renders the tooltip" do
        get "show", params: { id: user.id }
        expect(response.body).to have_text("Email blocked")
        expect(response.body).to have_text("example.com blocked")
      end
    end
  end

  describe "POST 'mark_compliant'" do
    let(:user) { create(:user) }

    it "flags seller as compliant" do
      post :mark_compliant, params: { id: user.id }

      expect(SaveToMongoWorker).to have_enqueued_sidekiq_job("user_risk_state", anything)
    end

    context "when error is raised" do
      before do
        allow_any_instance_of(User).to receive(:mark_compliant!).and_raise("Error!")
      end

      it "rescues and returns error message" do
        post :mark_compliant, params: { id: user.id }

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq("Error!")
      end
    end
  end

  describe "refund balance logic", :vcr, :sidekiq_inline do
    describe "POST 'refund_balance'" do
      before do
        @admin_user = create(:admin_user)
        sign_in @admin_user
        @user = create(:user)
        product = create(:product, user: @user)
        @purchase = create(:purchase, link: product, purchase_state: "in_progress", chargeable: create(:chargeable))
        @purchase.process!
        @purchase.increment_sellers_balance!
        @purchase.mark_successful!
      end

      it "refunds user's purchases if the user is suspended" do
        @user.flag_for_fraud(author_id: @admin_user.id)
        @user.suspend_for_fraud(author_id: @admin_user.id)
        post :refund_balance, params: { id: @user.id }
        expect(@purchase.reload.stripe_refunded).to be(true)
      end

      it "does not refund user's purchases if the user is not suspended" do
        post :refund_balance, params: { id: @user.id }
        expect(@purchase.reload.stripe_refunded).to_not be(true)
      end
    end
  end

  describe "POST flag_for_explicit_nsfw_tos_violation_from_iffy" do
    let(:seller) { create(:user) }
    let!(:product) { create(:product, user: seller) }

    it "flags the user for explicit NSFW TOS violation" do
      expect do
        post :flag_for_explicit_nsfw_tos_violation_from_iffy, params: { id: seller.id }
      end.to change { seller.reload.flagged_for_explicit_nsfw? }.from(false).to(true)
         .and have_enqueued_mail(ContactingCreatorMailer, :flagged_for_explicit_nsfw_tos_violation).with(seller.id)

      expect(product.reload.alive?).to eq false
      expect(seller.comments.last.author_name).to eq "iffy"
      expect(seller.comments.last.content).to include("All products were unpublished because this user was selling sexually explicit / fetish-oriented content.")
      expect(response).to be_successful
    end
  end
end
