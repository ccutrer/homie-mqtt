# frozen_string_literal: true

module MQTT
  module Homie
    class Property < Base
      attr_reader :node, :datatype, :format, :unit, :value

      def initialize(node, id, name, datatype, value = nil, format: nil, retained: true, unit: nil, &block)
        raise ArgumentError, "Invalid Homie datatype" unless %s{string integer float boolean enum color}
        raise ArgumentError, "retained must be boolean" unless [true, false].include?(retained)
        raise ArgumentError, "format must be nil or a string" unless format.nil? || format.is_a?(String)
        raise ArgumentError, "unit must be nil or a string" unless unit.nil? || unit.is_a?(String)
        super(id, name)
        @node = node
        @datatype = datatype
        @format = format
        @retained = retained
        @unit = unit
        @value = value
        @published = false
        @block = block
      end

      def device
        node.device
      end

      def topic
        "#{node.topic}/#{id}"
      end

      def retained?
        @retained
      end

      def settable?
        !!@block
      end

      def value=(value)
        if @value != value
          @value = value
          mqtt.publish(topic, value.to_s, retained?, 1) if @published
        end
      end

      def unit=(unit)
        if unit != @unit
          @unit = unit
          if @published
            device.init do
              mqtt.publish("#{topic}/$unit", unit.to_s, true, 1)
            end
          end
        end
      end

      def format=(format)
        if format != @format
          @format = format
          if @published
            device.init do
              mqtt.publish("#{topic}/$format", format.to_s, true, 1)
            end
          end
        end
      end

      def set(value)
        @block.call(self, value)
      end

      def mqtt
        node.mqtt
      end

      def publish
        return if @published

        mqtt.publish("#{topic}/$name", name, true, 1)
        mqtt.publish("#{topic}/$datatype", datatype.to_s, true, 1)
        mqtt.publish("#{topic}/$format", format, true, 1) if format
        mqtt.publish("#{topic}/$settable", "false", true, 1) unless settable?
        mqtt.publish("#{topic}/$retained", "false", true, 1) unless retained?
        mqtt.publish("#{topic}/$unit", unit, true, 1) if unit
        mqtt.subscribe("#{topic}/set") if settable?
        mqtt.publish(topic, value.to_s, retained?, 1) if value

        @published = true
      end

      def unpublish
        return unless @published
        @published = false

        mqtt.unsubscribe("#{topic}/set") if settable?
      end
    end
  end
end
