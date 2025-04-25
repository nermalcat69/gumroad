# frozen_string_literal: true

namespace :admin do
  get "action_call_dashboard", to: "action_call_dashboard#index"

  resources :users, only: [:show, :destroy], defaults: { format: "html" } do
    scope module: :users do
      resource :impersonator, only: [:create, :destroy]
      resources :payouts, only: [:index, :show], shallow: true do
        collection do
          post :pause
          post :resume
        end
      end
    end
    resources :service_charges, only: :index
    member do
      post :probation_with_reminder
      post :mark_compliant
      post :mark_compliant_from_iffy
      post :suspend_for_fraud
      post :suspend_for_fraud_from_iffy
      post :flag_for_explicit_nsfw_tos_violation_from_iffy
      post :suspend_for_tos_violation
      post :put_on_probation
      post :flag_for_fraud
      post :refund_balance
      get :stats
      post :verify
    end
  end

  get "/users/:user_id/guids", to: "compliance/guids#index", as: :compliance_guids

  resource :block_email_domains, only: [:show, :update]
  resource :unblock_email_domains, only: [:show, :update]
  resource :suspend_users, only: [:show, :update]

  resources :affiliates, only: [:index, :show], defaults: { format: "html" }

  resources :links, only: [:show], defaults: { format: "html" }

  resources :products, controller: "links", only: [:show, :destroy] do
    member do
      get :purchases
      get :views_count
      get :sales_stats
    end
    resource :staff_picked, only: [:create], controller: "products/staff_picked"
  end

  resources :payouts, only: [:index]
  resources :comments, only: :create

  resources :purchases, only: [:show] do
    member do
      post :refund
      post :refund_for_fraud
    end
  end

  resources :merchant_accounts, only: [:show] do
    member do
      get :live_attributes
    end
  end

  # Payouts
  resources :payments, controller: "users/payouts", only: [:show]

  # Search
  get "/search_users", to: "search#users", as: :search_users
  get "/search_purchases", to: "search#purchases", as: :search_purchases

  # Compliance
  scope module: "compliance" do
    resources :guids, only: [:show]
    resources :cards, only: [:index] do
      collection do
        post :refund
      end
    end
  end

  constraints(lambda { |request| request.env["warden"].authenticate? && request.env["warden"].user.is_team_member? }) do
    mount SidekiqWebCSP.new(Sidekiq::Web) => :sidekiq, as: :sidekiq_web
    mount FlipperCSP.new(Flipper::UI.app(Flipper)) => :features, as: :flipper_ui
  end
end
