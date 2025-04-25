# frozen_string_literal: true

require "spec_helper"

describe RiskMailer do
  describe "when suspending a user for fraud" do
    before do
      @user = create(:user)
      @mail = RiskMailer.user_suspended_for_fraud(@user.id)
    end

    it "has the proper information" do
      expect(@mail.to).to eq [ApplicationMailer::RISK_EMAIL]
      expect(@mail.subject).to match(@user.id.to_s)
      expect(@mail.body.encoded).to match("#{@user.id} has been suspended")
    end
  end

  describe "send user TOS violation email" do
    before do
      @user = create(:user)
      @admin_risk_user = create(:user, email: "admin_risk@gumroad.com")
      @product = create(:product, name: "test product")
    end

    it "returns violation reason" do
      mail = RiskMailer.user_flagged_for_tos_violation("test@test.com", "intellectual property infringement", @admin_risk_user.id, @product.id)
      expect(mail.body.encoded).to include("intellectual property infringement")
    end

    it "returns chargeback violation email text" do
      mail = RiskMailer.user_flagged_for_tos_violation("test@test.com", "high chargeback rate", @admin_risk_user.id, @product.id)
      expect(mail.body.encoded).to include("over the industry acceptable standard of 1%.")
    end
  end

  describe "suspend user for tos violation reminder" do
    before do
      @user = create(:user)
      @mail = RiskMailer.suspend_user_for_tos_violation(@user.id)
    end

    it "has a user id in subject" do
      expect(@mail.subject).to match(@user.id.to_s)
    end

    it "emails compliance, and only compliance" do
      expect(@mail.to).to eq [ApplicationMailer::RISK_EMAIL]
    end
  end

  describe "user suspension for fraud notification" do
    before do
      @user = create(:user)
      @mail = RiskMailer.user_suspension_for_fraud_notification(@user.id)
    end

    it "sends email to suspended user" do
      expect(@mail.to).to eq([@user.email])
      expect(@mail.from).to eq([ApplicationMailer::NOREPLY_EMAIL])
      expect(@mail.body.encoded).to include("forced to suspend your sales")
      expect(@mail.body.encoded).to include("will not be able to continue working with you")
      expect(@mail.body.encoded).to include("contact us and we will review your account ASAP")
    end
  end

  describe "user suspension for ToS violation notification" do
    before do
      @user = create(:user)
      @mail = RiskMailer.user_suspension_for_tos_violation_notification(@user.id)
    end

    it "sends email to suspended user" do
      expect(@mail.to).to eq([@user.email])
      expect(@mail.from).to eq([ApplicationMailer::NOREPLY_EMAIL])
      expect(@mail.body.encoded).to include("possible violations of our")
      expect(@mail.body.encoded).to include("Terms of Service")
    end
  end

  describe "probation_with_reminder" do
    before do
      @days = 20
      @user = create(:user)
      @mail = RiskMailer.probation_with_reminder(@user.id, @days)
    end

    it "sends email to probated user" do
      expect(@mail.to).to eq([@user.email])
    end

    it "sends email about probation" do
      expect(@mail.subject).to include("your Gumroad account")
      expect(@mail.body.encoded).to include("higher-than-average chargeback rate")
      expect(@mail.body.encoded).to include("pause your payouts for #{@days} days")
      expect(@mail.body.encoded).to include("cannot be paid until #{@days} days have passed")
    end
  end

  describe "probation_review" do
    before do
      @user = create(:user)
      @mail = RiskMailer.probation_review(@user.id)
    end

    it "has the user's name in subject" do
      expect(@mail.subject).to match(@user.display_name)
    end

    it "sends the email to the risk address" do
      expect(@mail.to).to eq [ApplicationMailer::RISK_EMAIL]
    end
  end
end
