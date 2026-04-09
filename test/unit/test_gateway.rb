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

  private

  def build_mock_redis_with_hit(response)
    embedding = EMBEDDING
    payload   = MessagePack.pack({ "embedding" => embedding, "response" => response })
    key       = "llm_optimizer:cache:#{Digest::SHA256.hexdigest(embedding.pack("f*"))}"

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
end
