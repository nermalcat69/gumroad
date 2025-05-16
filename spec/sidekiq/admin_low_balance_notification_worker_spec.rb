# frozen_string_literal: true

describe AdminLowBalanceNotificationWorker do
  describe "#perform" do
    context "when balance is lower than configured threshold" do
      before do
        @user = create(:user, unpaid_balance_cents: -200_00, name: "Test user")
        product = create(:product, user: @user)
        @purchase = create(:purchase, link: product)
      end

      it "sends the AdminMailer.low_balance_notify email" do
        expect do
          described_class.new.perform(@purchase.id)
        end.to change { ActionMailer::Base.deliveries.count }.by(1)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to include("Low balance for creator - Test user")
      end
    end

    context "when balance is higher than configured threshold" do
      before do
        @user = create(:user, unpaid_balance_cents: -40_00)
        product = create(:product, user: @user)
        @purchase = create(:purchase, link: product)
      end

      it "doesn't send the AdminMailer.low_balance_notify email" do
        expect do
          described_class.new.perform(@purchase.id)
        end.to_not change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
