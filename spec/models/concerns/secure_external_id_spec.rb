# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecureExternalId do
  let(:test_class) do
    Class.new do
      include SecureExternalId

      def self.name
        "TestClass"
      end

      def self.find_by(conditions)
        new if conditions[:id] == 123
      end

      def id
        123
      end
    end
  end

  let(:test_instance) { test_class.new }

  before do
    allow(GlobalConfig).to receive(:dig).with(:secure_external_id, default: {}).and_return({
                                                                                             primary_key_version: "1",
                                                                                             keys: {
                                                                                               "1" => "a" * 32 # 32 byte key for aes-256-gcm
                                                                                             }
                                                                                           })
  end

  describe "#secure_external_id" do
    it "generates an encrypted token" do
      token = test_instance.secure_external_id(scope: "test")
      expect(token).to be_a(String)
      expect(token.length).to be >= 50
    end

    it "raises error when primary key not found" do
      allow(GlobalConfig).to receive(:dig).with(:secure_external_id, default: {}).and_return({
                                                                                               primary_key_version: "2",
                                                                                               keys: { "1" => "a" * 32 }
                                                                                             })

      expect do
        test_instance.secure_external_id(scope: "test")
      end.to raise_error(SecureExternalId::KeyNotFound)
    end
  end

  describe ".find_by_secure_external_id" do
    it "finds record with valid token" do
      token = test_instance.secure_external_id(scope: "test")
      expect(test_class.find_by_secure_external_id(token, scope: "test")).to be_a(test_class)
    end

    it "returns nil for invalid token" do
      expect(test_class.find_by_secure_external_id("invalid", scope: "test")).to be_nil
    end

    it "returns nil for wrong scope" do
      token = test_instance.secure_external_id(scope: "test")
      expect(test_class.find_by_secure_external_id(token, scope: "wrong")).to be_nil
    end

    it "checks for expired token" do
      expires_at = 1.hour.from_now
      token = test_instance.secure_external_id(scope: "test", expires_at: expires_at)

      travel_to 45.minutes.from_now do
        expect(test_class.find_by_secure_external_id(token, scope: "test")).to be_a(test_class)
      end

      travel_to 2.hours.from_now do
        expect(test_class.find_by_secure_external_id(token, scope: "test")).to be_nil # expired
      end
    end


    it "returns nil for non-string input" do
      expect(test_class.find_by_secure_external_id(123, scope: "test")).to be_nil
    end

    it "returns nil for invalid base64" do
      expect(test_class.find_by_secure_external_id("invalid base64!", scope: "test")).to be_nil
    end

    it "returns nil for wrong model name" do
      other_class = Class.new do
        include SecureExternalId

        def self.name
          "OtherClass"
        end

        def id
          123
        end
      end

      token = test_instance.secure_external_id(scope: "test")
      expect(other_class.find_by_secure_external_id(token, scope: "test")).to be_nil
    end
  end
end
