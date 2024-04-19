# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../data_container_tests'
require_relative '../common_aggregator_tests'
require 'new_relic/agent/span_event_aggregator'

module NewRelic
  module Agent
    class SpanEventAggregatorTest < Minitest::Test
      def setup
        @additional_config = {:'distributed_tracing.enabled' => true}
        NewRelic::Agent.config.add_config_for_testing(@additional_config)

        nr_freeze_process_time
        events = NewRelic::Agent.instance.events
        @event_aggregator = SpanEventAggregator.new(events)
      end

      def teardown
        NewRelic::Agent.config.remove_config(@additional_config)
        NewRelic::Agent.agent.drop_buffered_data
      end

      # Helpers for DataContainerTests

      def create_container
        @event_aggregator
      end

      def populate_container(sampler, n)
        n.times do |i|
          generate_event("whatever#{i}")
        end
      end

      include NewRelic::DataContainerTests

      # Helpers for CommonAggregatorTests

      def generate_event(name = 'operation_name', options = {})
        guid = fake_guid(16)

        event = [
          {
            'name' => name,
            'priority' => options[:priority] || rand,
            'sampled' => false,
            'guid' => guid,
            'traceId' => guid,
            'timestamp' => Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond),
            'duration' => rand,
            'category' => 'custom'
          },
          {},
          {}
        ]

        @event_aggregator.record(event: event)
      end

      def last_events
        aggregator.harvest![1]
      end

      def aggregator
        @event_aggregator
      end

      def name_for(event)
        event[0]['name']
      end

      def enabled_key
        :'span_events.enabled'
      end

      include NewRelic::CommonAggregatorTests

      def test_supportability_metrics_for_span_events
        # NOTE: with_config won't work here, as the underlying capacity value
        #       ends up inside of a cached callback, so we'll directly alter
        #       the aggregator buffer's capacity and revert the change
        #       afterwards in an ensure block
        original_capacity = aggregator.instance_variable_get(:@buffer).capacity

        seen = 25_000
        captured = 10_000
        aggregator.instance_variable_get(:@buffer).capacity = captured

        seen.times { generate_event }

        assert_equal captured, last_events.size
        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSeen' => {call_count: seen}})
        assert_metrics_recorded({'Supportability/SpanEvent/TotalEventsSent' => {call_count: captured}})
        assert_metrics_recorded({'Supportability/SpanEvent/Discarded' => {call_count: (seen - captured)}})
      ensure
        aggregator.instance_variable_get(:@buffer).capacity = original_capacity
      end
    end
  end
end
