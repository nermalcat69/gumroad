# frozen_string_literal: true

require "spec_helper"

describe "Impersonate", type: :feature, js: true do
  let(:admin) { create(:admin_user, name: "Gumlord") }
  let(:seller) { create(:named_seller) }

  before do
    login_as(admin)
  end

  it "becomes Seller, and unbecomes" do
    visit admin_user_path(seller)
    click_on("Become")
    wait_for_ajax

    visit settings_main_path
    wait_for_ajax
    within_section "User details", section_element: :section do
      expect(page).to have_input_labelled "Email", with: seller.email
    end

    within "nav[aria-label='Main']" do
      toggle_disclosure(seller.display_name)
      click_on("Unbecome")
      wait_for_ajax
      expect(page.current_path).to eq(admin_user_path(seller))
    end
  end
end
