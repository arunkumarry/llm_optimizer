# frozen_string_literal: true

require_relative "../test_helper"

# Stub Redis::BaseError for unit tests (no real Redis gem needed)
unless defined?(Redis::BaseError)
  module Redis
    class BaseError < StandardError; end
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
    def bad_redis.set(*) = raise(Redis::BaseError, "connection refused")
    cache = LlmOptimizer::SemanticCache.new(bad_redis, threshold: 0.9, ttl: 3600)
    suppress_stderr { cache.store(EMBEDDING, RESPONSE) }
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
    query  = [0.0, 1.0, 0.0] # orthogonal — similarity = 0.0
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
    def bad_redis.keys(*) = raise(Redis::BaseError, "timeout")
    cache = LlmOptimizer::SemanticCache.new(bad_redis, threshold: 0.9, ttl: 3600)
    suppress_stderr { assert_nil cache.lookup(EMBEDDING) }
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

  # cache_scope

  def test_store_with_scope_uses_scoped_prefix
    cache = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.9, ttl: 3600, cache_scope: "user_123")
    cache.store(EMBEDDING, RESPONSE)
    key = @redis.keys("llm_optimizer:cache:user_123:*").first
    refute_nil key
    assert key.start_with?("llm_optimizer:cache:user_123:")
  end

  def test_lookup_with_scope_only_finds_in_scope
    # Store in scope A
    cache_a = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.9, ttl: 3600, cache_scope: "scope_a")
    cache_a.store(EMBEDDING, "response a")

    # Store in scope B
    cache_b = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.9, ttl: 3600, cache_scope: "scope_b")
    cache_b.store(EMBEDDING, "response b")

    # Lookup in scope A should find response a
    assert_equal "response a", cache_a.lookup(EMBEDDING)

    # Lookup in scope B should find response b
    assert_equal "response b", cache_b.lookup(EMBEDDING)

    # Lookup with no scope should find nothing (prefix is different)
    assert_nil @cache.lookup(EMBEDDING)
  end

  def test_cache_key_with_scope
    cache = LlmOptimizer::SemanticCache.new(@redis, threshold: 0.9, ttl: 3600, cache_scope: "my_scope")
    key = cache.send(:cache_key, EMBEDDING)
    assert_match(/^llm_optimizer:cache:my_scope:[a-f0-9]{64}$/, key)
  end

  # round trip

  def test_store_then_lookup_round_trip
    embedding = [0.5, 0.5, 0.5]
    response  = "round trip response"
    @cache.store(embedding, response)
    assert_equal response, @cache.lookup(embedding)
  end

  private

  def suppress_stderr
    old = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = old
  end
end
