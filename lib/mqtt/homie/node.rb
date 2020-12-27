# frozen_string_literal: true

module MQTT
  module Homie
    class Node < Base
      attr_reader :device, :type, :properties

      def initialize(device, id, name, type)
        super(id, name)
        @device = device
        @type = type
        @properties = {}
        @published = false
      end

      def topic
        "#{device.topic}/#{id}"
      end

      def property(*args, **kwargs, &block)
        device.init do |prior_state|
          property = Property.new(self, *args, **kwargs, &block)
          raise ArgumentError, "Property '#{property.id}' already exists on '#{id}'" if @properties.key?(property.id)
          @properties[property.id] = property
          property.publish if prior_state == :ready
        end
        self
      end

      def remove_property(id)
        return unless (property = properties[id])
        init do
          property.unpublish
          @properties.delete(id)
          mqtt.publish("#{topic}/$properties", properties.keys.join(","), true, 1) if @published
        end
      end

      def mqtt
        device.mqtt
      end

      def publish
        unless @published
          mqtt.publish("#{topic}/$name", name, true, 1)
          mqtt.publish("#{topic}/$type", @type.to_s, true, 1)
          @published = true
        end
 
        mqtt.publish("#{topic}/$properties", properties.keys.join(","), true, 1)
        properties.each_value(&:publish)
      end

      def unpublish
        return unless @published
        @published = false

        properties.each_value(&:unpublish)
      end
    end
  end
end
