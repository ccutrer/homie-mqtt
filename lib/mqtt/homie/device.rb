# frozen_string_literal: true

require 'mqtt'

module MQTT
  module Homie
    class Device < Base
      attr_reader :root_topic, :state, :mqtt

      def initialize(id, name, root_topic: nil, mqtt: nil, &block)
        super(id, name)
        @root_topic = @root_topic || "homie"
        @state = :init
        @nodes = {}
        @published = false
        @block = block
        mqtt = MQTT::Client.new(mqtt) if mqtt.is_a?(String)
        @mqtt = mqtt || MQTT::Client.new
        @mqtt.set_will("#{topic}/$state", "lost", true)
        @mqtt.connect
      end

      def device
        self
      end

      def topic
        "#{root_topic}/#{id}"
      end

      def node(*args, **kwargs)
        init do |prior_state|
          node = Node.new(self, *args, **kwargs)
          raise ArgumentError, "Node '#{node.id}' already exists" if @nodes.key?(node.id)
          @nodes[node.id] = node
          yield node if block_given?
          if prior_state == :ready
            node.publish
            mqtt.publish("#{topic}/$nodes", @nodes.keys.join(","), true, 1)
          end
        end
        self
      end

      def remove_node(id)
        return unless (node = @nodes[id])
        init do
          node.unpublish
          @nodes.delete(id)
          mqtt.publish("#{topic}/$nodes", @nodes.keys.join(","), true, 1) if @published
        end
      end

      def [](id)
        @nodes[id]
      end

      def publish
        return if @published

        mqtt.publish("#{topic}/$homie", "4.0.0", true, 1)
        mqtt.publish("#{topic}/$name", name, true, 1)
        mqtt.publish("#{topic}/$state", @state.to_s, true, 1)

        @subscription_thread = Thread.new do
          mqtt.get do |topic, value|
            match = topic.match(topic_regex)
            node = @nodes[match[:node]] if match
            property = node[match[:property]] if node

            unless property&.settable?
              @block&.call(topic, value)
              next
            end

            property.set(value)
          end
        end
 
        mqtt.publish("#{topic}/$nodes", @nodes.keys.join(","), true, 1)
        @nodes.each_value(&:publish)
        mqtt.publish("#{topic}/$state", (@state = :ready).to_s, true, 1)

        @published = true
      end

      def disconnect
        @published = false
        mqtt.disconnect
        @subscription_thread&.kill
      end

      def join
        @subscription_thread&.join
      end

      def init
        if state == :init
          yield(state)
          return
        end

        prior_state = state
        mqtt.publish("#{topic}/$state", (state = :init).to_s, true, 1)
        yield(prior_state)
        mqtt.publish("#{topic}/$state", (state = :ready).to_s, true, 1)
        nil
      end

      private

      def topic_regex
        @topic_regex ||= Regexp.new("^#{Regexp.escape(topic)}/(?<node>#{REGEX})/(?<property>#{REGEX})/set$")
      end
    end
  end
end
