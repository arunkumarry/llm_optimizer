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

  def test_default_embedding_model_is_nil
    assert_nil LlmOptimizer::Configuration.new.embedding_model
  end

  def test_default_simple_model_is_nil
    assert_nil LlmOptimizer::Configuration.new.simple_model
  end

  def test_default_complex_model_is_nil
    assert_nil LlmOptimizer::Configuration.new.complex_model
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

  def test_default_cache_scope_is_nil
    assert_nil LlmOptimizer::Configuration.new.cache_scope
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

  # Grouped settings and flat aliases

  def test_grouped_setting_readable_via_flat_alias
    config = LlmOptimizer::Configuration.new
    config.cache.enabled = true
    assert_equal true, config.use_semantic_cache
  end

  def test_flat_alias_writes_into_group
    config = LlmOptimizer::Configuration.new
    config.route_to = :simple
    assert_equal :simple, config.routing.mode
  end

  def test_with_tools_aliases_tools
    config = LlmOptimizer::Configuration.new
    config.with_tools = [{ name: "t" }]
    assert_equal [{ name: "t" }], config.tools
  end

  def test_merge_copies_group_settings
    base = LlmOptimizer::Configuration.new
    other = LlmOptimizer::Configuration.new
    other.cache.threshold = 0.5
    base.merge!(other)
    assert_in_delta 0.5, base.cache.threshold
  end

  def test_merge_does_not_reset_group_settings
    base = LlmOptimizer::Configuration.new
    base.routing.simple_model = "my-model"
    base.merge!(LlmOptimizer::Configuration.new)
    assert_equal "my-model", base.routing.simple_model
  end

  # Adapter resolution

  def test_resolved_adapter_nil_without_adapter_or_callers
    assert_nil LlmOptimizer::Configuration.new.resolved_adapter
  end

  def test_resolved_adapter_wraps_legacy_callers
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    assert_instance_of LlmOptimizer::Adapters::Legacy, config.resolved_adapter
  end

  def test_resolved_adapter_resolves_symbols
    config = LlmOptimizer::Configuration.new
    config.adapter = :anthropic
    assert_instance_of LlmOptimizer::Adapters::Anthropic, config.resolved_adapter
  end

  def test_resolved_adapter_returns_instance_untouched
    adapter = LlmOptimizer::Adapters::Custom.new(chat: ->(_m, model:) { model })
    config = LlmOptimizer::Configuration.new
    config.adapter = adapter
    assert_same adapter, config.resolved_adapter
  end

  # Validation

  def test_configure_raises_on_invalid_route_mode
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.configure { |c| c.route_to = :fastest }
    end
  end

  def test_configure_raises_on_out_of_range_threshold
    assert_raises(LlmOptimizer::ConfigurationError) do
      LlmOptimizer.configure { |c| c.similarity_threshold = 1.5 }
    end
  end

  def test_validate_raises_without_adapter
    err = assert_raises(LlmOptimizer::ConfigurationError) { LlmOptimizer.validate! }
    assert_includes err.message, "adapter"
  end

  def test_validate_raises_when_cache_enabled_without_redis_url
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    config.embedding_caller = ->(_t) { [1.0] }
    config.cache.enabled = true
    err = assert_raises(LlmOptimizer::ConfigurationError) { config.validate! }
    assert_includes err.message, "redis_url"
  end

  def test_validate_raises_when_cache_enabled_without_embedding_support
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    config.redis_url = "redis://localhost:6379"
    config.cache.enabled = true
    err = assert_raises(LlmOptimizer::ConfigurationError) { config.validate! }
    assert_includes err.message, "embedding"
  end

  def test_validate_passes_with_complete_cache_config
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    config.embedding_caller = ->(_t) { [1.0] }
    config.redis_url = "redis://localhost:6379"
    config.cache.enabled = true
    config.routing.simple_model  = "simple-x"
    config.routing.complex_model = "complex-x"
    assert config.validate!
  end

  def test_validate_raises_when_routing_models_missing
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    err = assert_raises(LlmOptimizer::ConfigurationError) { config.validate! }
    assert_includes err.message, "routing.simple_model"
    assert_includes err.message, "routing.complex_model"
  end

  def test_validate_simple_mode_requires_only_simple_model
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    config.routing.mode = :simple
    config.routing.simple_model = "simple-x"
    assert config.validate!
  end

  def test_validate_complex_mode_requires_only_complex_model
    config = LlmOptimizer::Configuration.new
    config.llm_caller = ->(_p, **_k) { "hi" }
    config.routing.mode = :complex
    config.routing.complex_model = "complex-x"
    assert config.validate!
  end
end
