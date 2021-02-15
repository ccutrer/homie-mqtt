# frozen_string_literal: true

module MQTT
  module Homie
    class Base
      REGEX = "[a-z0-9][a-z0-9\-]*"

      attr_reader :id, :name

      def initialize(id, name)
        raise ArgumentError, "Invalid Homie ID '#{id}'" unless id.is_a?(String) && id =~ Regexp.new("^#{REGEX}$")
        @id = id
        @name = name
      end

      def name=(value)
        if name != value
          name = value
          if @published
            device.init do
              mqtt.publish("#{topic}/$name", name, retain: true, qos: 1)
            end
          end
        end
      end
    end
  end
end
