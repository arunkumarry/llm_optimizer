# frozen_string_literal: true

require_relative "../test_helper"

class TestConfiguration < Minitest::Test
  def setup
    LlmOptimizer.reset_configuration!
  end

  # Defaults

  def test_default_use_semantic_cache_is_false
    assert_equal false, LlmOptimizer::Configuration.new.use_semantic_cache
  end

  def test_default_compress_prompt_is_false
    assert_equal false, LlmOptimizer::Configuration.new.compress_prompt
  end

  def test_default_manage_history_is_false
    assert_equal false, LlmOptimizer::Configuration.new.manage_history
  end

  def test_default_route_to_is_auto
    assert_equal :auto, LlmOptimizer::Configuration.new.route_to
  end

  def test_default_similarity_threshold
    assert_in_delta 0.96, LlmOptimizer::Configuration.new.similarity_threshold
  end

  def test_default_token_budget
    assert_equal 4000, LlmOptimizer::Configuration.new.token_budget
  end

  def test_default_embedding_model
    assert_equal "text-embedding-3-small", LlmOptimizer::Configuration.new.embedding_model
  end

  def test_default_simple_model
    assert_equal "gpt-4o-mini", LlmOptimizer::Configuration.new.simple_model
  end

  def test_default_complex_model
    assert_equal "claude-3-5-sonnet-20241022", LlmOptimizer::Configuration.new.complex_model
  end

  def test_default_debug_logging_is_false
    assert_equal false, LlmOptimizer::Configuration.new.debug_logging
  end

  def test_default_timeout_seconds
    assert_equal 5, LlmOptimizer::Configuration.new.timeout_seconds
  end

  def test_default_cache_ttl
    assert_equal 86_400, LlmOptimizer::Configuration.new.cache_ttl
  end

  def test_default_logger_is_logger_instance
    assert_instance_of Logger, LlmOptimizer::Configuration.new.logger
  end

  def test_default_llm_caller_is_nil
    assert_nil LlmOptimizer::Configuration.new.llm_caller
  end

  def test_default_embedding_caller_is_nil
    assert_nil LlmOptimizer::Configuration.new.embedding_caller
  end

  def test_default_redis_url_is_nil
    assert_nil LlmOptimizer::Configuration.new.redis_url
  end

  # Setters

  def test_setting_known_key
    config = LlmOptimizer::Configuration.new
    config.compress_prompt = true
    assert_equal true, config.compress_prompt
  end

  def test_setting_llm_caller
    config = LlmOptimizer::Configuration.new
    caller = ->(_p, **_kwargs) { "response" }
    config.llm_caller = caller
    assert_equal caller, config.llm_caller
  end

  # Unknown key guard

  def test_unknown_key_raises_configuration_error
    config = LlmOptimizer::Configuration.new
    assert_raises(LlmOptimizer::ConfigurationError) { config.unknown_key = "value" }
  end

  def test_unknown_key_error_includes_key_name
    config = LlmOptimizer::Configuration.new
    err = assert_raises(LlmOptimizer::ConfigurationError) { config.bad_key = "x" }
    assert_includes err.message, "bad_key"
  end

  def test_unknown_reader_raises_configuration_error
    config = LlmOptimizer::Configuration.new
    assert_raises(LlmOptimizer::ConfigurationError) { config.nonexistent }
  end

  # merge!

  def test_merge_copies_explicitly_set_keys
    base = LlmOptimizer::Configuration.new
    other = LlmOptimizer::Configuration.new
    other.compress_prompt = true
    base.merge!(other)
    assert_equal true, base.compress_prompt
  end

  def test_merge_does_not_reset_unmentioned_keys
    base = LlmOptimizer::Configuration.new
    base.token_budget = 9999
    other = LlmOptimizer::Configuration.new
    other.compress_prompt = true
    base.merge!(other)
    assert_equal 9999, base.token_budget
    assert_equal true, base.compress_prompt
  end

  def test_merge_overwrites_existing_key
    base = LlmOptimizer::Configuration.new
    base.simple_model = "old-model"
    other = LlmOptimizer::Configuration.new
    other.simple_model = "new-model"
    base.merge!(other)
    assert_equal "new-model", base.simple_model
  end

  def test_merge_with_empty_config_changes_nothing
    base = LlmOptimizer::Configuration.new
    base.token_budget = 1234
    base.merge!(LlmOptimizer::Configuration.new)
    assert_equal 1234, base.token_budget
  end

  # LlmOptimizer.configure

  def test_configure_yields_configuration_instance
    yielded = nil
    LlmOptimizer.configure { |c| yielded = c }
    assert_instance_of LlmOptimizer::Configuration, yielded
  end

  def test_configure_merges_into_global_config
    LlmOptimizer.configure { |c| c.token_budget = 8000 }
    assert_equal 8000, LlmOptimizer.configuration.token_budget
  end

  def test_configure_multiple_times_merges_without_reset
    LlmOptimizer.configure { |c| c.token_budget = 8000 }
    LlmOptimizer.configure { |c| c.compress_prompt = true }
    assert_equal 8000, LlmOptimizer.configuration.token_budget
    assert_equal true, LlmOptimizer.configuration.compress_prompt
  end

  def test_reset_configuration_restores_defaults
    LlmOptimizer.configure { |c| c.token_budget = 9999 }
    LlmOptimizer.reset_configuration!
    assert_equal 4000, LlmOptimizer.configuration.token_budget
  end
end
