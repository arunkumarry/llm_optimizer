# frozen_string_literal: true

require_relative "../test_helper"

# Stub Redis::BaseError for unit tests (no real Redis gem needed)
module Redis
  class BaseError < StandardError; end
end unless defined?(Redis::BaseError)

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

class TestSemanticCache < Minitest::Test
  EMBEDDING = [1.0, 0.0, 0.0].freeze
  RESPONSE  = "cached response"

  def setup
    @redis = MockRedis.new
    @cache = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.9, ttl: 3600)
  end

  # store

  def test_store_writes_to_redis
    @cache.store(EMBEDDING, RESPONSE)
    keys = @redis.keys("llm_optimizer:cache:*")
    assert_equal 1, keys.length
  end

  def test_store_key_uses_namespace
    @cache.store(EMBEDDING, RESPONSE)
    key = @redis.keys("llm_optimizer:cache:*").first
    assert key.start_with?("llm_optimizer:cache:")
  end

  def test_store_sets_ttl
    @cache.store(EMBEDDING, RESPONSE)
    key = @redis.keys("llm_optimizer:cache:*").first
    assert_equal 3600, @redis.ttl(key)
  end

  def test_store_swallows_redis_error
    bad_redis = Object.new
    def bad_redis.set(*); raise Redis::BaseError, "connection refused"; end
    cache = LlmOptimizer::SemanticCache.new(bad_redis, threshold: 0.9, ttl: 3600)
    # Should not raise — Redis errors are swallowed
    cache.store(EMBEDDING, RESPONSE)
  end

  # lookup

  def test_lookup_returns_nil_when_empty
    assert_nil @cache.lookup(EMBEDDING)
  end

  def test_lookup_returns_response_on_exact_match
    @cache.store(EMBEDDING, RESPONSE)
    assert_equal RESPONSE, @cache.lookup(EMBEDDING)
  end

  def test_lookup_returns_nil_below_threshold
    cache = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.99, ttl: 3600)
    stored = [1.0, 0.0, 0.0]
    query  = [0.0, 1.0, 0.0]  # orthogonal — similarity = 0.0
    cache.store(stored, RESPONSE)
    assert_nil cache.lookup(query)
  end

  def test_lookup_returns_best_match_above_threshold
    @cache.store([1.0, 0.0, 0.0], "first")
    @cache.store([0.0, 1.0, 0.0], "second")
    result = @cache.lookup([1.0, 0.0, 0.0])
    assert_equal "first", result
  end

  def test_lookup_treats_redis_error_as_miss
    bad_redis = Object.new
    def bad_redis.keys(*); raise Redis::BaseError, "timeout"; end
    cache = LlmOptimizer::SemanticCache.new(bad_redis, threshold: 0.9, ttl: 3600)
    assert_nil cache.lookup(EMBEDDING)
  end

  # cosine_similarity

  def test_cosine_similarity_identical_vectors
    sim = @cache.cosine_similarity([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
    assert_in_delta 1.0, sim, 1e-9
  end

  def test_cosine_similarity_orthogonal_vectors
    sim = @cache.cosine_similarity([1.0, 0.0], [0.0, 1.0])
    assert_in_delta 0.0, sim, 1e-9
  end

  def test_cosine_similarity_opposite_vectors
    sim = @cache.cosine_similarity([1.0, 0.0], [-1.0, 0.0])
    assert_in_delta(-1.0, sim, 1e-9)
  end

  def test_cosine_similarity_is_symmetric
    a = [0.3, 0.5, 0.8]
    b = [0.1, 0.9, 0.2]
    assert_in_delta @cache.cosine_similarity(a, b), @cache.cosine_similarity(b, a), 1e-9
  end

  def test_cosine_similarity_bounded_between_minus1_and_1
    a = [0.3, -0.5, 0.8]
    b = [0.1, 0.9, -0.2]
    sim = @cache.cosine_similarity(a, b)
    assert sim >= -1.0
    assert sim <= 1.0
  end

  def test_cosine_similarity_zero_vector_returns_zero
    assert_equal 0.0, @cache.cosine_similarity([0.0, 0.0], [1.0, 2.0])
  end

  # round trip

  def test_store_then_lookup_round_trip
    embedding = [0.5, 0.5, 0.5]
    response  = "round trip response"
    @cache.store(embedding, response)
    assert_equal response, @cache.lookup(embedding)
  end
end
