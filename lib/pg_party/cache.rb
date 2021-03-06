# frozen_string_literal: true

require "thread"

module PgParty
  class Cache
    LOCK = Mutex.new

    def initialize
      # automatically initialize a new hash when
      # accessing an object id that doesn't exist
      @store = Hash.new { |h, k| h[k] = { models: {}, partitions: nil, partitions_with_subpartitions: nil } }
    end

    def clear!
      LOCK.synchronize { @store.clear }

      nil
    end

    def fetch_model(key, child_table, &block)
      return block.call unless caching_enabled?

      LOCK.synchronize { fetch_value(@store[key][:models], child_table.to_sym, block) }
    end

    def fetch_partitions(key, include_subpartitions, &block)
      return block.call unless caching_enabled?
      sub_key = include_subpartitions ? :partitions_with_subpartitions : :partitions

      LOCK.synchronize { fetch_value(@store[key], sub_key, block) }
    end

    private

    def caching_enabled?
      PgParty.config.caching
    end

    def fetch_value(subhash, key, block)
      entry = subhash[key]

      if entry.nil? || entry.expired?
        entry = Entry.new(block.call)
        subhash[key] = entry
      end

      entry.value
    end

    class Entry
      attr_reader :value

      def initialize(value)
        @value = value
        @timestamp = Time.now
      end

      def expired?
        ttl.positive? && Time.now - @timestamp > ttl
      end

      private

      def ttl
        PgParty.config.caching_ttl
      end
    end

    private_constant :Entry
  end
end
