# frozen_string_literal: true

module MQTT
  module Homie
    class Property < Base
      attr_reader :node, :datatype, :format, :unit, :value

      def initialize(node, id, name, datatype, value = nil, format: nil, retained: true, unit: nil, &block)
        raise ArgumentError, "Invalid Homie datatype" unless %i[string integer float boolean enum color datetime duration].include?(datatype)
        raise ArgumentError, "retained must be boolean" unless [true, false].include?(retained)
        format = format.join(",") if format.is_a?(Array) && datatype == :enum
        if %i{integer float}.include?(datatype) && format.is_a?(Range)
          raise ArgumentError "only inclusive ranges are supported" if format.exclude_end?
          format = "#{format.begin}:#{format.end}"
        end
        raise ArgumentError, "format must be nil or a string" unless format.nil? || format.is_a?(String)
        raise ArgumentError, "unit must be nil or a string" unless unit.nil? || unit.is_a?(String)
        raise ArgumentError, "format is required for enums" if datatype == :enum && format.nil?
        raise ArgumentError, "format is required for colors" if datatype == :color && format.nil?
        raise ArgumentError, "format must be either rgb or hsv for colors" if datatype == :color && !%w{rgb hsv}.include?(format.to_s)
        raise ArgumentError, "an initial value cannot be provided for a non-retained property" if !value.nil? && !retained

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
        if @value != value
          @value = value if retained?
          publish_value if @published
        end
      end

      def unit=(unit)
        if unit != @unit
          @unit = unit
          if @published
            device.init do
              mqtt.publish("#{topic}/$unit", unit.to_s, retain: true, qos: 1)
            end
          end
        end
      end

      def format=(format)
        if format != @format
          @format = format
          if @published
            device.init do
              mqtt.publish("#{topic}/$format", format.to_s, retain: true, qos: 1)
            end
          end
        end
      end

      def range
        case datatype
        when :enum; format.split(',')
        when :integer; Range.new(*format.split(':').map(&:to_i))
        when :float; Range.new(*format.split(':').map(&:to_f))
        else; raise MethodNotImplemented
        end
      end

      def set(value)
        case datatype
        when :boolean
          return unless %w{true false}.include?(value)
          value = value == 'true'
        when :integer
          return unless value =~ /^-?\d+$/
          value = value.to_i
          return unless range.include?(value) if format
        when :float
          return unless value =~ /^-?(?:\d+|\d+\.|\.\d+|\d+\.\d+)(?:[eE]-?\d+)?$/
          value = value.to_f
          return unless range.include?(value) if format
        when :enum
          return unless range.include?(value)
        when :color
          return unless value =~ /^\d{1,3},\d{1,3},\d{1,3}$/
          value = value.split(',').map(&:to_i)
          if format == 'rgb'
            return if value.max > 255
          elsif format == 'hsv'
            return if value.first > 360 || value[1..2].max > 100
          end
        when :datetime
          begin
            value = Time.parse(value)
          rescue ArgumentError
            return
          end
        when :duration
          begin
            value = ActiveSupport::Duration.parse(value)
          rescue ActiveSupport::Duration::ISO8601Parser::ParsingError
            return
          end
        end

        @block.arity == 2 ? @block.call(value, self) : @block.call(value)
      end

      def mqtt
        node.mqtt
      end

      def publish
        return if @published

        mqtt.batch_publish do
          mqtt.publish("#{topic}/$name", name, retain: true, qos: 1)
          mqtt.publish("#{topic}/$datatype", datatype.to_s, retain: true, qos: 1)
          mqtt.publish("#{topic}/$format", format, retain: true, qos: 1) if format
          mqtt.publish("#{topic}/$settable", "true", retain: true, qos: 1) if settable?
          mqtt.publish("#{topic}/$retained", "false", retain: true, qos: 1) unless retained?
          mqtt.publish("#{topic}/$unit", unit, retain: true, qos: 1) if unit
          publish_value unless value.nil?
          subscribe
        end

        @published = true
      end

      def subscribe
        mqtt.subscribe("#{topic}/set") if settable?
      end

      def unpublish
        return unless @published
        @published = false

        mqtt.publish("#{topic}/$name", retain: true, qos: 0)
        mqtt.publish("#{topic}/$datatype", retain: true, qos: 0)
        mqtt.publish("#{topic}/$format", retain: true, qos: 0) if format
        mqtt.publish("#{topic}/$settable", retain: true, qos: 0) if settable?
        mqtt.publish("#{topic}/$retained", retain: true, qos: 0) unless retained?
        mqtt.publish("#{topic}/$unit", retain: true, qos: 0) if unit
        mqtt.unsubscribe("#{topic}/set") if settable?
        mqtt.publish(topic, retain: retained?, qos: 0) if !value.nil? && retained?
      end

      private

      def publish_value
        serialized = value
        serialized = serialized&.iso8601 if %i[datetime duration].include?(datatype)
        serialized = serialized.to_s

        node.device.logger&.debug("publishing #{serialized.inspect} to #{topic}")
        mqtt.publish(topic, serialized, retain: retained?, qos: 1)
      end
    end
  end
end
