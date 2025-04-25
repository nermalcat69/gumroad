# frozen_string_literal: true

describe ProbationReviewEmailWorker do
  before do
    @user = create(:user)
  end

  describe "#perform" do
    it "sends the email if the user is still on probation" do
      expect do
        @user.put_on_probation!(author_id: @user.id)
        described_class.new.perform(@user.id)
      end.to change { ActionMailer::Base.deliveries.count }.by(1)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to include(@user.display_name)
      expect(mail.subject).to include("probation review")
    end

    it "does not send the email if the user is not on probation" do
      expect do
        described_class.new.perform(@user.id)
      end.to_not change { ActionMailer::Base.deliveries.count }
    end
  end
end
