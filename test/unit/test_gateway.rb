# frozen_string_literal: true

require_relative "../test_helper"
require "digest"
require "msgpack"
require "mocha/minitest"

# Stub Redis::BaseError for unit tests (no real Redis gem needed)
unless defined?(Redis::BaseError)
  module Redis
    class BaseError < StandardError; end
  end
end

class TestGateway < Minitest::Test
  LLM_RESPONSE = "This is the LLM response"
  EMBEDDING    = [1.0, 0.0, 0.0].freeze

  def setup
    LlmOptimizer.reset_configuration!
    LlmOptimizer.configure do |c|
      c.llm_caller      = ->(_prompt, **_kwargs) { LLM_RESPONSE }
      c.logger          = Logger.new(nil) # silence logs in tests
    end
  end

  def teardown
    LlmOptimizer.reset_configuration!
  end

  # OptimizeResult fields

  def test_returns_optimize_result
    result = LlmOptimizer.optimize("What is Redis?")
    assert_instance_of LlmOptimizer::OptimizeResult, result
  end

  def test_result_has_response
    result = LlmOptimizer.optimize("What is Redis?")
    assert_equal LLM_RESPONSE, result.response
  end

  def test_result_has_model
    result = LlmOptimizer.optimize("What is Redis?")
    refute_nil result.model
  end

  def test_result_has_model_tier
    result = LlmOptimizer.optimize("What is Redis?")
    assert_includes %i[simple complex], result.model_tier
  end

  def test_result_has_cache_status
    result = LlmOptimizer.optimize("What is Redis?")
    assert_includes %i[hit miss], result.cache_status
  end

  def test_result_has_original_tokens
    result = LlmOptimizer.optimize("What is Redis?")
    assert_kind_of Integer, result.original_tokens
    assert result.original_tokens.positive?
  end

  def test_result_has_latency_ms
    result = LlmOptimizer.optimize("What is Redis?")
    assert_kind_of Float, result.latency_ms
    assert result.latency_ms >= 0
  end

  # Model routing

  def test_short_prompt_uses_simple_model
    LlmOptimizer.configure { |c| c.simple_model = "fast-model" }
    result = LlmOptimizer.optimize("Hi there")
    assert_equal "fast-model", result.model
    assert_equal :simple, result.model_tier
  end

  def test_complex_prompt_uses_complex_model
    LlmOptimizer.configure { |c| c.complex_model = "smart-model" }
    result = LlmOptimizer.optimize("Please analyze and refactor this entire codebase architecture")
    assert_equal "smart-model", result.model
    assert_equal :complex, result.model_tier
  end

  # Compression

  def test_compression_sets_compressed_tokens
    LlmOptimizer.configure { |c| c.compress_prompt = true }
    result = LlmOptimizer.optimize("the quick brown fox is jumping over the lazy dog")
    refute_nil result.compressed_tokens
    assert result.compressed_tokens <= result.original_tokens
  end

  def test_no_compression_leaves_compressed_tokens_nil
    LlmOptimizer.configure { |c| c.compress_prompt = false }
    result = LlmOptimizer.optimize("hello world")
    assert_nil result.compressed_tokens
  end

  # Per-call block config

  def test_block_yields_configuration_instance
    yielded = nil
    LlmOptimizer.optimize("hello") { |c| yielded = c }
    assert_instance_of LlmOptimizer::Configuration, yielded
  end

  def test_per_call_config_overrides_global
    LlmOptimizer.configure { |c| c.route_to = :complex }
    result = LlmOptimizer.optimize("Hi") { |c| c.route_to = :simple }
    assert_equal :simple, result.model_tier
  end

  # Cache miss (no Redis)

  def test_returns_miss_when_no_redis
    result = LlmOptimizer.optimize("What is Redis?")
    assert_equal :miss, result.cache_status
  end

  # Semantic cache with mock Redis

  def test_cache_hit_returns_cached_response
    mock_redis = build_mock_redis_with_hit("cached answer")
    LlmOptimizer.configure do |c|
      c.use_semantic_cache  = true
      c.redis_url           = "redis://localhost:6379"
      c.embedding_caller    = ->(_text) { EMBEDDING }
    end

    LlmOptimizer.stubs(:build_redis).returns(mock_redis)
    result = LlmOptimizer.optimize("What is Redis?")
    assert_equal :hit, result.cache_status
    assert_equal "cached answer", result.response
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  def test_cache_miss_calls_llm
    called = false
    LlmOptimizer.configure do |c|
      c.use_semantic_cache = true
      c.redis_url          = "redis://localhost:6379"
      c.embedding_caller   = ->(_text) { EMBEDDING }
      c.llm_caller         = lambda { |_prompt, **_kwargs|
        called = true
        LLM_RESPONSE
      }
    end

    empty_redis = build_mock_redis_empty
    LlmOptimizer.stubs(:build_redis).returns(empty_redis)
    LlmOptimizer.optimize("What is Redis?")
    assert called
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  # wrap_client

  def test_wrap_client_prepends_wrapper_module
    klass = Class.new
    LlmOptimizer.wrap_client(klass)
    assert klass.ancestors.include?(LlmOptimizer::WrapperModule)
  end

  def test_wrap_client_is_idempotent
    klass = Class.new
    LlmOptimizer.wrap_client(klass)
    LlmOptimizer.wrap_client(klass)
    count = klass.ancestors.count(LlmOptimizer::WrapperModule)
    assert_equal 1, count
  end

  # Error handling / resilience

  def test_raises_configuration_error_when_no_llm_caller
    LlmOptimizer.reset_configuration!
    LlmOptimizer.configure { |c| c.logger = Logger.new(nil) }
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.optimize("hello")
    end
  end

  def test_embedding_error_treated_as_cache_miss
    LlmOptimizer.configure do |c|
      c.use_semantic_cache = true
      c.redis_url          = "redis://localhost:6379"
      c.embedding_caller   = ->(_text) { raise LlmOptimizer::EmbeddingError, "API down" }
    end
    result = LlmOptimizer.optimize("What is Redis?")
    assert_equal :miss, result.cache_status
    assert_equal LLM_RESPONSE, result.response
  end

  # Logging

  def test_info_log_does_not_contain_prompt
    log_output = StringIO.new
    LlmOptimizer.configure { |c| c.logger = Logger.new(log_output) }
    prompt = "super secret prompt content xyz123"
    LlmOptimizer.optimize(prompt)
    refute_includes log_output.string, prompt
  end

  def test_info_log_contains_cache_status
    log_output = StringIO.new
    LlmOptimizer.configure { |c| c.logger = Logger.new(log_output) }
    LlmOptimizer.optimize("hello world")
    assert_includes log_output.string, "cache_status"
  end

  def test_info_log_contains_latency_ms
    log_output = StringIO.new
    LlmOptimizer.configure { |c| c.logger = Logger.new(log_output) }
    LlmOptimizer.optimize("hello world")
    assert_includes log_output.string, "latency_ms"
  end

  def test_debug_log_contains_prompt_when_debug_logging_enabled
    log_output = StringIO.new
    LlmOptimizer.configure do |c|
      c.logger        = Logger.new(log_output)
      c.debug_logging = true
    end
    prompt = "debug prompt content"
    LlmOptimizer.optimize(prompt)
    assert_includes log_output.string, prompt
  end

  # ConversationStore integration

  def test_conversation_id_with_messages_raises_configuration_error
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.optimize("hello", conversation_id: "conv-1", messages: [{ role: "user", content: "hi" }])
    end
  end

  def test_conversation_id_without_redis_url_raises_configuration_error
    # redis_url is nil by default after reset
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.optimize("hello", conversation_id: "conv-1")
    end
  end

  def test_conversation_id_loads_history_calls_llm_saves_history
    stored = {}
    mock_redis = build_mock_redis_for_conversation(stored)

    LlmOptimizer.configure { |c| c.redis_url = "redis://localhost:6379" }
    LlmOptimizer.stubs(:build_redis).returns(mock_redis)

    result = LlmOptimizer.optimize("What is 2+2?", conversation_id: "conv-abc")

    assert_equal LLM_RESPONSE, result.response
    # Redis should have been written with the new messages
    key = "llm_optimizer:conversation:conv-abc"
    assert stored.key?(key), "Expected Redis key to be set"
    saved = JSON.parse(stored[key], symbolize_names: true)
    assert_equal "user",      saved.last(2).first[:role]
    assert_equal "assistant", saved.last[:role]
    assert_equal LLM_RESPONSE, saved.last[:content]
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  # clear_conversation

  def test_clear_conversation_returns_true_when_key_exists
    mock_redis = Object.new
    mock_redis.define_singleton_method(:del) { |_key| 1 }
    LlmOptimizer.configure { |c| c.redis_url = "redis://localhost:6379" }
    LlmOptimizer.stubs(:build_redis).returns(mock_redis)
    assert_equal true, LlmOptimizer.clear_conversation("conv-1")
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  def test_clear_conversation_returns_false_when_key_absent
    mock_redis = Object.new
    mock_redis.define_singleton_method(:del) { |_key| 0 }
    LlmOptimizer.configure { |c| c.redis_url = "redis://localhost:6379" }
    LlmOptimizer.stubs(:build_redis).returns(mock_redis)
    assert_equal false, LlmOptimizer.clear_conversation("conv-missing")
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  def test_clear_conversation_raises_error_on_redis_failure
    mock_redis = Object.new
    mock_redis.define_singleton_method(:del) { |_key| raise Redis::BaseError, "connection refused" }
    LlmOptimizer.configure { |c| c.redis_url = "redis://localhost:6379" }
    LlmOptimizer.stubs(:build_redis).returns(mock_redis)
    err = assert_raises(LlmOptimizer::Error) { LlmOptimizer.clear_conversation("conv-1") }
    assert_includes err.message, "Redis error in clear_conversation"
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  def test_clear_conversation_raises_configuration_error_when_no_redis_url
    # redis_url is nil after reset
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.clear_conversation("conv-1")
    end
  end

  def test_calls_without_conversation_id_make_zero_redis_interactions
    redis_calls = 0
    spy_redis = Object.new
    spy_redis.define_singleton_method(:get) do |*_|
      redis_calls += 1
      nil
    end
    spy_redis.define_singleton_method(:set) do |*_|
      redis_calls += 1
      nil
    end
    spy_redis.define_singleton_method(:keys) do |*_|
      redis_calls += 1
      []
    end

    LlmOptimizer.stubs(:build_redis).returns(spy_redis)
    LlmOptimizer.optimize("hello world")
    assert_equal 0, redis_calls
  ensure
    LlmOptimizer.unstub(:build_redis)
  end

  private

  def build_mock_redis_with_hit(response)
    embedding = EMBEDDING
    # Must use "G*" (64-bit) to match SemanticCache#cache_key and store format
    payload   = MessagePack.pack({ "embedding" => embedding.pack("G*"), "response" => response })
    key       = "llm_optimizer:cache:#{Digest::SHA256.hexdigest(embedding.pack("G*"))}"

    mock = Object.new
    mock.define_singleton_method(:keys) { |_pattern| [key] }
    mock.define_singleton_method(:get)  { |_key| payload }
    mock.define_singleton_method(:set)  { |*_args| nil }
    mock
  end

  def build_mock_redis_empty
    mock = Object.new
    mock.define_singleton_method(:keys) { |_pattern| [] }
    mock.define_singleton_method(:set)  { |*_args| nil }
    mock
  end

  def build_mock_redis_for_conversation(store = {})
    mock = Object.new
    mock.define_singleton_method(:get)  { |key| store[key] }
    mock.define_singleton_method(:set)  do |key, value, *_opts|
      store[key] = value
      "OK"
    end
    mock
  end
end
