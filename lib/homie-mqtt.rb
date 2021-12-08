# frozen_string_literal: true

module MQTT
  module Homie
    class << self
      def escape_id(id)
        id.downcase.gsub(/[^a-z0-9\-]/, "-").sub(/^[^a-z0-9]+/, "")
      end
    end
  end
end

require "mqtt/homie/base"
require "mqtt/homie/device"
require "mqtt/homie/node"
require "mqtt/homie/property"
