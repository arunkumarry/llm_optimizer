# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Suppress warnings from third-party gems (e.g. prop_check)
module SuppressGemWarnings
  GEM_PATHS = Gem.path.map { |p| Regexp.escape(p) }.join("|")
  GEM_RE    = Regexp.new(GEM_PATHS).freeze

  def warn(msg, *args, **kwargs)
    return if msg.to_s.match?(GEM_RE)

    super
  end
end
Warning.extend(SuppressGemWarnings)

require "llm_optimizer"
require "minitest/autorun"

class MockRedis
  def initialize
    @store = {}
    @ttls  = {}
  end

  def set(key, value, ex: nil)
    @store[key] = value
    @ttls[key]  = ex
  end

  def get(key)
    @store[key]
  end

  def keys(pattern)
    prefix = pattern.chomp("*")
    @store.keys.select { |k| k.start_with?(prefix) }
  end

  def ttl(key)
    @ttls[key] || -1
  end
end
