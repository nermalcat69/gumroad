# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"
require "shared_examples/authorize_called"

describe Admin::Users::ImpersonatorsController do
  it_behaves_like "inherits from Admin::BaseController"

  let(:seller) { create(:named_seller) }
  before do
    sign_in create(:admin_user)
  end

  describe "POST 'create'" do
    it_behaves_like "authorize called for action", :post, :create do
      let(:policy_klass) { Admin::Impersonators::UserPolicy }
      let(:record) { seller }
      let(:request_params) { { user_id: seller.id.to_s } }
    end

    it "impersonates user" do
      post :create, params: { user_id: seller.id.to_s }

      expect(response).to redirect_to(dashboard_url)
      expect(flash[:notice]).to eq("You are now impersonating Seller!")
      expect(controller.impersonating?).to be(true)
      expect(controller.impersonated_user).to eq(seller)
    end
  end

  describe "DELETE 'destroy'" do
    context "with admin signed in and impersonating user" do
      let(:user) { create(:user) }

      before do
        admin = create(:admin_user)
        sign_in admin
        controller.impersonate_user(user)
      end

      it "stops impersonating user and returns the location of the admin page of the impersonated user" do
        expect(controller.impersonating?).to be(true)
        delete :destroy, xhr: true, params: { user_id: create(:user) }

        expect(controller.impersonating?).to be(false)
        expect(controller.impersonated_user).to be(nil)
        expect(response).to be_successful
        expect(response.parsed_body["redirect_to"]).to eq(admin_user_url(user))
      end
    end
  end
end
