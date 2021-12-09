# frozen_string_literal: true

module MQTT
  module Homie
    class Node < Base
      attr_reader :device, :type

      def initialize(device, id, name, type)
        super(id, name)
        @device = device
        @type = type
        @properties = {}
        @published = false
      end

      def inspect
        "#<MQTT::Homie::Node #{topic} name=#{full_name.inspect}, type=#{type.inspect}>"
      end

      def full_name
        return name if device.count == 1

        "#{device.name} #{name}"
      end

      def topic
        "#{device.topic}/#{id}"
      end

      ruby2_keywords def property(*args, &block)
        device.init do |prior_state|
          property = Property.new(self, *args, &block)
          raise ArgumentError, "Property '#{property.id}' already exists on '#{id}'" if @properties.key?(property.id)

          @properties[property.id] = property
          property.publish if prior_state == :ready
          property
        end
      end

      def remove_property(id)
        return false unless (property = @properties[id])

        init do
          property.unpublish
          @properties.delete(id)
          mqtt.publish("#{topic}/$properties", @properties.keys.join(","), retain: true, qos: 1) if published?
        end
        true
      end

      def [](id)
        @properties[id]
      end

      def each(&block)
        @properties.each_value(&block)
      end

      def mqtt
        device.mqtt
      end

      # takes a hash with property names as keys, and values as values
      def batch_update(hash)
        mqtt.batch_publish do
          hash.each do |(k, v)|
            self[k].value = v
          end
        end
      end

      def published?
        @published
      end

      def publish
        mqtt.batch_publish do
          unless published?
            mqtt.publish("#{topic}/$name", name, retain: true, qos: 1)
            mqtt.publish("#{topic}/$type", @type.to_s, retain: true, qos: 1)
            @published = true
          end

          mqtt.publish("#{topic}/$properties", @properties.keys.join(","), retain: true, qos: 1)
          @properties.each_value(&:publish)
        end
      end

      def unpublish
        return unless published?

        @published = false

        mqtt.publish("#{topic}/$name", retain: true, qos: 0)
        mqtt.publish("#{topic}/$type", retain: true, qos: 0)
        mqtt.publish("#{topic}/$properties", retain: true, qos: 0)

        @properties.each_value(&:unpublish)
      end
    end
  end
end
