require_relative "lib/mqtt/homie/version"

Gem::Specification.new do |s|
  s.name = 'homie-mqtt'
  s.version = MQTT::Homie::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.com'"
  s.homepage = "https://github.com/ccutrer/homie-mqtt"
  s.summary = "Library for publishing devices that conform to the Homie spec."
  s.license = "MIT"

  s.files = Dir["{lib}/**/*"]

  s.add_dependency 'mqtt-ccutrer', "~> 1.0"

  s.add_development_dependency 'byebug', "~> 9.0"
  s.add_development_dependency 'rake', "~> 13.0"
end
