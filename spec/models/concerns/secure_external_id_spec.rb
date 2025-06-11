# frozen_string_literal: true

require 'rails_helper'

# Dummy class for testing the concern
class SecurableProduct < ApplicationRecord
  self.table_name = 'products'
  include SecureExternalId
end

RSpec.describe SecureExternalId, type: :model do
  let!(:product) { SecurableProduct.create! }
  let(:credentials) do
    {
      secure_external_id: {
        primary_key_version: '2',
        keys: {
          '1' => 'cFf5A795pGW597M9aJ3pG4a3A5n9K7m3', # 32 bytes for aes-256-gcm
          '2' => 'kK9a4B7r9G6jE3m5V8d4C2b1A9p7H4n2'  # 32 bytes for aes-256-gcm
        }
      }
    }
  end
  let(:old_key_encryptor) do
    key = credentials.dig(:secure_external_id, :keys, '1')
    ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm')
  end

  before do
    allow(Rails.application).to receive(:credentials).and_return(credentials)
  end

  describe '#secure_external_id' do
    it 'generates a URL-safe, decryptable token' do
      token = product.secure_external_id(scope: 'default')
      expect(token).to be_a(String)
      found_product = SecurableProduct.find_by_secure_external_id(token, scope: 'default')
      expect(found_product).to eq(product)
    end

    it 'generates a token with a specific scope' do
      token = product.secure_external_id(scope: 'test_scope')
      found_product = SecurableProduct.find_by_secure_external_id(token, scope: 'test_scope')
      expect(found_product).to eq(product)
    end
  end

  describe '.find_by_secure_external_id' do
    it 'finds the record for a valid token with default scope' do
      token = product.secure_external_id(scope: 'default')
      expect(SecurableProduct.find_by_secure_external_id(token, scope: 'default')).to eq(product)
    end

    it 'returns nil for a token used with the wrong scope' do
      token = product.secure_external_id(scope: 'correct_scope')
      expect(SecurableProduct.find_by_secure_external_id(token, scope: 'wrong_scope')).to be_nil
    end

    it 'returns nil for a token with an invalid signature (tampered)' do
      token = product.secure_external_id(scope: 'default')
      tampered_token = token.slice(0..-2)
      expect(SecurableProduct.find_by_secure_external_id(tampered_token, scope: 'default')).to be_nil
    end

    it 'returns nil for an expired token' do
      token = product.secure_external_id(scope: 'default', expires_at: 1.second.ago)
      expect(SecurableProduct.find_by_secure_external_id(token, scope: 'default')).to be_nil
    end

    it 'returns nil for a token from a different model' do
      class AnotherSecurableModel < ApplicationRecord
        self.table_name = 'users'
        include SecureExternalId
      end
      token = product.secure_external_id(scope: 'default')
      expect(AnotherSecurableModel.find_by_secure_external_id(token, scope: 'default')).to be_nil
    end

    it 'returns nil for a malformed token' do
      expect(SecurableProduct.find_by_secure_external_id('not-a-real-token', scope: 'default')).to be_nil
    end

    it 'returns nil for a token with an unknown version' do
      outer_payload = { v: '99', d: 'some_data' }
      token = Base64.urlsafe_encode64(outer_payload.to_json, padding: false)
      expect(SecurableProduct.find_by_secure_external_id(token, scope: 'default')).to be_nil
    end

    it 'returns nil for a non-string token' do
      expect(SecurableProduct.find_by_secure_external_id(nil, scope: 'default')).to be_nil
      expect(SecurableProduct.find_by_secure_external_id(123, scope: 'default')).to be_nil
    end
  end

  describe 'key rotation' do
    it 'encrypts using the primary key version (v2)' do
      token = product.secure_external_id(scope: 'default')
      decoded_json = Base64.urlsafe_decode64(token)
      outer_payload = JSON.parse(decoded_json, symbolize_names: true)

      expect(outer_payload[:v]).to eq('2')
    end

    it 'can decrypt a token created with an old key (v1)' do
      # Manually create a token with the old key
      inner_payload = { model: 'SecurableProduct', id: product.id, scp: 'default' }
      encrypted_data = old_key_encryptor.encrypt_and_sign(inner_payload.to_json)
      outer_payload = { v: '1', d: encrypted_data }
      old_token = Base64.urlsafe_encode64(outer_payload.to_json, padding: false)

      # Expect the current code to decrypt it successfully
      found_product = SecurableProduct.find_by_secure_external_id(old_token, scope: 'default')
      expect(found_product).to eq(product)
    end
  end
end
