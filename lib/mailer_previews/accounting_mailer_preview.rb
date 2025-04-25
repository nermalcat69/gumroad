# frozen_string_literal: true

class AccountingMailerPreview < ActionMailer::Preview
  def email_outstanding_balances_csv
    AccountingMailer.email_outstanding_balances_csv
  end
end
