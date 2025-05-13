# frozen_string_literal: true

require "time"

module MQTT
  module Homie
    class Property < Base
      attr_reader :node, :datatype, :format, :unit, :value

      def initialize(node,
                     id,
                     name,
                     datatype,
                     value = nil,
                     format: nil,
                     retained: true,
                     unit: nil,
                     non_standard_value_check: nil,
                     &block)
        raise ArgumentError, "Invalid Homie datatype" unless %i[string
                                                                integer
                                                                float
                                                                boolean
                                                                enum
                                                                color
                                                                datetime
                                                                duration].include?(datatype)
        raise ArgumentError, "retained must be boolean" unless [true, false].include?(retained)
        raise ArgumentError, "unit must be nil or a string" unless unit.nil? || unit.is_a?(String)
        if !value.nil? && !retained
          raise ArgumentError, "an initial value cannot be provided for a non-retained property"
        end

        super(id, name)

        @node = node
        @datatype = datatype
        self.format = format
        @retained = retained
        @unit = unit
        @value = value
        @published = false
        @non_standard_value_check = non_standard_value_check
        @block = block
      end

      def inspect
        result = +"#<MQTT::Homie::Property #{topic} name=#{full_name.inspect}, datatype=#{datatype.inspect}"
        result << ", format=#{format.inspect}" if format
        result << ", unit=#{unit.inspect}" if unit
        result << ", settable=true" if settable?
        result << if retained?
                    ", value=#{value.inspect}"
                  else
                    ", retained=false"
                  end
        result << ">"
        result.freeze
      end

      def full_name
        "#{node.full_name} #{name}"
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
        return if @value == value

        @value = value if retained?
        publish_value(value) if published?
      end

      def unit=(unit)
        return if unit == @unit

        @unit = unit
        return unless published?

        device.init do
          mqtt.publish("#{topic}/$unit", unit.to_s, retain: true, qos: 1)
        end
      end

      def format=(format)
        return if format == @format

        format = format.join(",") if format.is_a?(Array) && datatype == :enum
        if %i[integer float].include?(datatype) && format.is_a?(Range)
          raise ArgumentError, "only inclusive ranges are supported" if format.last.is_a?(Float) && format.exclude_end?

          last = format.end
          last -= 1 if format.exclude_end?

          format = "#{format.begin}:#{last}"
        end
        raise ArgumentError, "format must be nil or a string" unless format.nil? || format.is_a?(String)
        raise ArgumentError, "format is required for enums" if datatype == :enum && format.nil?
        raise ArgumentError, "format is required for colors" if datatype == :color && format.nil?
        if datatype == :color && !%w[rgb hsv].include?(format.to_s)
          raise ArgumentError, "format must be either rgb or hsv for colors"
        end

        @format = format
        return unless published?

        device.init do
          mqtt.publish("#{topic}/$format", format.to_s, retain: true, qos: 1)
        end
      end

      def range
        return nil unless format

        case datatype
        when :enum then format.split(",")
        when :integer then Range.new(*format.split(":").map(&:to_i))
        when :float then Range.new(*format.split(":").map(&:to_f))
        else; raise MethodNotImplemented
        end
      end

      def set(value)
        casted_value = case datatype
                       when :boolean
                         %w[true false].include?(value) ? value == "true" : nil
                       when :integer
                         /^-?\d+$/.match?(value) && value.to_i
                       when :float
                         /^-?(?:\d+|\d+\.|\.\d+|\d+\.\d+)(?:[eE]-?\d+)?$/.match?(value) && value.to_f
                       when :enum
                         value
                       when :color
                         /^\d{1,3},\d{1,3},\d{1,3}$/.match?(value) && value = value.split(",").map(&:to_i)
                       when :datetime
                         begin
                           value = Time.parse(value)
                         rescue ArgumentError
                           nil
                         end
                       when :duration
                         begin
                           value = ActiveSupport::Duration.parse(value)
                         rescue ActiveSupport::Duration::ISO8601Parser::ParsingError
                           nil
                         end
                       end
        case datatype
        when :integer, :float
          casted_value = nil if format && !range.cover?(casted_value)
        when :enum
          casted_value = nil if format && !range.include?(casted_value)
        when :color
          casted_value = nil if (format == "rgb" && value.max > 255) ||
                                (format == "hsb" && (value.first > 360 || value[1..2].max > 100))
        end

        casted_value = @non_standard_value_check&.call(value) if casted_value.nil?
        return if casted_value.nil?

        (@block.arity == 2) ? @block.call(casted_value, self) : @block.call(casted_value)
      end

      def mqtt
        node.mqtt
      end

      def published?
        @published
      end

      def publish
        return if published?

        mqtt.batch_publish do
          if device.metadata?
            mqtt.publish("#{topic}/$name", name, retain: true, qos: 1)
            mqtt.publish("#{topic}/$datatype", datatype.to_s, retain: true, qos: 1)
            mqtt.publish("#{topic}/$format", format, retain: true, qos: 1) if format
            mqtt.publish("#{topic}/$settable", "true", retain: true, qos: 1) if settable?
            mqtt.publish("#{topic}/$retained", "false", retain: true, qos: 1) unless retained?
            mqtt.publish("#{topic}/$unit", unit, retain: true, qos: 1) if unit
          end
          publish_value(value) unless value.nil?
          subscribe
        end

        @published = true
      end

      def subscribe
        mqtt.subscribe("#{topic}/set") if settable?
      end

      def unpublish
        return unless published?

        @published = false

        if device.metadata?
          mqtt.publish("#{topic}/$name", retain: true, qos: 0)
          mqtt.publish("#{topic}/$datatype", retain: true, qos: 0)
          mqtt.publish("#{topic}/$format", retain: true, qos: 0) if format
          mqtt.publish("#{topic}/$settable", retain: true, qos: 0) if settable?
          mqtt.publish("#{topic}/$retained", retain: true, qos: 0) unless retained?
          mqtt.publish("#{topic}/$unit", retain: true, qos: 0) if unit
        end
        mqtt.unsubscribe("#{topic}/set") if settable?
        mqtt.publish(topic, retain: retained?, qos: 0) if !value.nil? && retained?
      end

      private

      def publish_value(value)
        serialized = value
        serialized = serialized&.iso8601 if %i[datetime duration].include?(datatype)
        serialized = serialized.to_s

        node.device.logger&.debug("publishing #{serialized.inspect} to #{topic}")
        mqtt.publish(topic, serialized, retain: retained?, qos: 1)
      end
    end
  end
end
