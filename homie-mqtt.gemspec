# frozen_string_literal: true

require_relative "lib/mqtt/homie/version"

Gem::Specification.new do |s|
  s.name = "homie-mqtt"
  s.version = MQTT::Homie::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.com'"
  s.homepage = "https://github.com/ccutrer/homie-mqtt"
  s.summary = "Library for publishing devices that conform to the Homie spec."
  s.license = "MIT"
  s.metadata = {
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir["{lib}/**/*"]

  s.required_ruby_version = ">= 2.5"

  s.add_dependency "mqtt-ccutrer", "~> 1.0", ">= 1.0.1"
  s.add_dependency "ruby2_keywords", "~> 0.0.5"

  s.add_development_dependency "byebug", "~> 9.0"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.23"
  s.add_development_dependency "rubocop-performance", "~> 1.12"
  s.add_development_dependency "rubocop-rake", "~> 0.6"
end
