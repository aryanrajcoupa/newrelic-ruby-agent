# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'thread'
require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module VM
      class MriVM
        @@slots_per_page = Hash.new do |hash, slot_size|
          # https://github.com/ruby/ruby/blob/v3_3_1/test/ruby/test_gc.rb#L490-L492
          multiple = slot_size / (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
          hash[slot_size] = (GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT] / multiple) - 1
        end

        def snapshot
          snap = Snapshot.new
          gather_stats(snap)
          snap
        end

        def gather_stats(snap)
          gather_gc_stats(snap)
          gather_ruby_vm_stats(snap)
          gather_thread_stats(snap)
          gather_gc_time(snap)
        end

        def gather_gc_stats(snap)
          if supports?(:gc_runs)
            snap.gc_runs = GC.count
          end

          if GC.respond_to?(:stat)
            gc_stats = GC.stat
            snap.total_allocated_object = gc_stats[:total_allocated_objects] || gc_stats[:total_allocated_object]
            snap.major_gc_count = gc_stats[:major_gc_count]
            snap.minor_gc_count = gc_stats[:minor_gc_count]
            snap.heap_live = gc_stats[:heap_live_slots] || gc_stats[:heap_live_slot] || gc_stats[:heap_live_num]
            snap.heap_free = gc_stats[:heap_free_slots] || gc_stats[:heap_free_slot] || gc_stats[:heap_free_num]
          end

          if GC.respond_to?(:stat_heap)
            GC.stat_heap.each do |i, s|
              # https://github.com/ruby/ruby/blob/v3_3_1/test/ruby/test_gc.rb#L494
              total_slots = s[:heap_eden_slots] + s[:heap_allocatable_pages] * @@slots_per_page[s[:slot_size]]
              attr_name = "@heap_#{i}_slots".to_s
              snap.instance_variable_set(attr_name, total_slots)
            end
          end
        end

        def gather_gc_time(snap)
          if supports?(:gc_total_time)
            snap.gc_total_time = NewRelic::Agent.instance.monotonic_gc_profiler.total_time_s
          end
        end

        def gather_ruby_vm_stats(snap)
          if supports?(:method_cache_invalidations)
            snap.method_cache_invalidations = RubyVM.stat[:global_method_state]
          end

          if supports?(:constant_cache_invalidations)
            snap.constant_cache_invalidations = RubyVM.stat[:global_constant_state]
          end
        end

        def gather_thread_stats(snap)
          snap.thread_count = Thread.list.size
        end

        def supports?(key)
          case key
          when :gc_runs, :total_allocated_object, :heap_live, :heap_free, :thread_count
            true
          when :gc_total_time
            NewRelic::LanguageSupport.gc_profiler_enabled?
          when :major_gc_count
            RUBY_VERSION >= '2.1.0'
          when :minor_gc_count
            RUBY_VERSION >= '2.1.0'
          when :method_cache_invalidations
            RUBY_VERSION >= '2.1.0' && RUBY_VERSION < '3.0.0'
          when :constant_cache_invalidations
            RUBY_VERSION >= '2.1.0'
          else
            false
          end
        end
      end
    end
  end
end
