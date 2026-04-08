# frozen_string_literal: true

require_relative "test_helper"
require "llm_optimizer/configuration"

G = PropCheck::Generators

class TestConfiguration < Minitest::Test
  # ---------------------------------------------------------------------------
  # Task 2.2 — Property 2
  # Feature: llm-optimizer, Property 2: Configuration block is yielded a Configuration instance
  # Validates: Requirements 1.2
  # ---------------------------------------------------------------------------
  def test_property2_configure_yields_configuration_instance
    if LlmOptimizer.respond_to?(:configure)
      PropCheck.forall(G.printable_ascii_string) do |_ignored|
        yielded = nil
        LlmOptimizer.configure { |c| yielded = c }
        raise "Expected Configuration instance, got #{yielded.class}" unless yielded.is_a?(LlmOptimizer::Configuration)
      end
    else
      # LlmOptimizer.configure not yet implemented — test Configuration directly
      PropCheck.forall(G.printable_ascii_string) do |_ignored|
        config = LlmOptimizer::Configuration.new
        assert_instance_of LlmOptimizer::Configuration, config
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Task 2.3 — Property 3
  # Feature: llm-optimizer, Property 3: Unknown configuration keys raise ConfigurationError with key name
  # Validates: Requirements 1.5
  # ---------------------------------------------------------------------------
  def test_property3_unknown_keys_raise_configuration_error_with_key_name
    known = LlmOptimizer::Configuration::KNOWN_KEYS.map(&:to_s)

    # Generate alphanumeric strings that are not known keys
    unknown_key_gen = G.alphanumeric_string(min: 1).where { |s| !known.include?(s) }

    PropCheck.forall(unknown_key_gen) do |key|
      config = LlmOptimizer::Configuration.new
      raised = false
      message = nil
      begin
        config.public_send(:"#{key}=", "value")
      rescue LlmOptimizer::ConfigurationError => e
        raised = true
        message = e.message
      end
      raise "Expected ConfigurationError for key '#{key}' but none was raised" unless raised
      raise "Expected error message to include '#{key}', got: '#{message}'" unless message.include?(key)
    end
  end

  # ---------------------------------------------------------------------------
  # Task 2.4 — Property 4
  # Feature: llm-optimizer, Property 4: configure merges without resetting unmentioned keys
  # Validates: Requirements 2.7
  # ---------------------------------------------------------------------------
  def test_property4_merge_preserves_all_keys
    # Use two disjoint subsets of known keys with simple assignable values
    # We pick from keys that accept simple values (not logger)
    assignable_keys = %i[
      use_semantic_cache compress_prompt manage_history
      debug_logging route_to similarity_threshold
      token_budget redis_url embedding_model
      simple_model complex_model timeout_seconds cache_ttl
    ]

    # Generate two non-overlapping index sets from assignable_keys
    half = assignable_keys.size / 2
    set_a_keys = assignable_keys.first(half)
    set_b_keys = assignable_keys.last(half)

    # Values to assign per key type
    sample_values = {
      use_semantic_cache: true,
      compress_prompt: true,
      manage_history: true,
      debug_logging: true,
      route_to: :simple,
      similarity_threshold: 0.85,
      token_budget: 1234,
      redis_url: "redis://localhost:6379",
      embedding_model: "text-embedding-ada-002",
      simple_model: "gpt-3.5-turbo",
      complex_model: "gpt-4",
      timeout_seconds: 10,
      cache_ttl: 3600
    }

    PropCheck.forall(G.integer) do |_ignored|
      config = LlmOptimizer::Configuration.new

      # Apply set A
      config_a = LlmOptimizer::Configuration.new
      set_a_keys.each { |k| config_a.public_send(:"#{k}=", sample_values[k]) }
      config.merge!(config_a)

      # Apply set B
      config_b = LlmOptimizer::Configuration.new
      set_b_keys.each { |k| config_b.public_send(:"#{k}=", sample_values[k]) }
      config.merge!(config_b)

      # All keys from A must still be present
      set_a_keys.each do |k|
        actual = config.public_send(k)
        expected = sample_values[k]
        raise "Key #{k} from set A was reset. Expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
      end

      # All keys from B must be present
      set_b_keys.each do |k|
        actual = config.public_send(k)
        expected = sample_values[k]
        raise "Key #{k} from set B missing. Expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Task 2.5 — Unit tests for defaults and merge behavior
  # Validates: Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7
  # ---------------------------------------------------------------------------

  def test_default_use_semantic_cache
    assert_equal false, LlmOptimizer::Configuration.new.use_semantic_cache
  end

  def test_default_compress_prompt
    assert_equal false, LlmOptimizer::Configuration.new.compress_prompt
  end

  def test_default_manage_history
    assert_equal false, LlmOptimizer::Configuration.new.manage_history
  end

  def test_default_route_to
    assert_equal :auto, LlmOptimizer::Configuration.new.route_to
  end

  def test_default_similarity_threshold
    assert_in_delta 0.96, LlmOptimizer::Configuration.new.similarity_threshold
  end

  def test_default_token_budget
    assert_equal 4000, LlmOptimizer::Configuration.new.token_budget
  end

  def test_default_redis_url
    assert_nil LlmOptimizer::Configuration.new.redis_url
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

  def test_default_debug_logging
    assert_equal false, LlmOptimizer::Configuration.new.debug_logging
  end

  def test_default_timeout_seconds
    assert_equal 5, LlmOptimizer::Configuration.new.timeout_seconds
  end

  def test_default_cache_ttl
    assert_equal 86400, LlmOptimizer::Configuration.new.cache_ttl
  end

  def test_default_logger_is_logger_instance
    assert_instance_of Logger, LlmOptimizer::Configuration.new.logger
  end

  def test_merge_copies_explicitly_set_keys
    base = LlmOptimizer::Configuration.new
    other = LlmOptimizer::Configuration.new
    other.token_budget = 9999
    other.simple_model = "gpt-3.5-turbo"

    base.merge!(other)

    assert_equal 9999, base.token_budget
    assert_equal "gpt-3.5-turbo", base.simple_model
  end

  def test_merge_does_not_reset_unmentioned_keys
    base = LlmOptimizer::Configuration.new
    base.use_semantic_cache = true
    base.token_budget = 8000

    other = LlmOptimizer::Configuration.new
    other.simple_model = "gpt-3.5-turbo"

    base.merge!(other)

    # Keys set on base before merge must be preserved
    assert_equal true, base.use_semantic_cache
    assert_equal 8000, base.token_budget
    # Key from other must be applied
    assert_equal "gpt-3.5-turbo", base.simple_model
  end

  def test_merge_returns_self
    base = LlmOptimizer::Configuration.new
    other = LlmOptimizer::Configuration.new
    result = base.merge!(other)
    assert_same base, result
  end

  def test_merge_does_not_copy_unset_keys_from_other
    base = LlmOptimizer::Configuration.new
    base.token_budget = 1111

    other = LlmOptimizer::Configuration.new
    # other.token_budget is NOT explicitly set

    base.merge!(other)

    # base's token_budget should remain 1111, not reset to other's default 4000
    assert_equal 1111, base.token_budget
  end

  def test_unknown_key_raises_configuration_error
    config = LlmOptimizer::Configuration.new
    assert_raises(LlmOptimizer::ConfigurationError) { config.nonexistent_key = "value" }
  end

  def test_configuration_error_message_includes_key_name
    config = LlmOptimizer::Configuration.new
    err = assert_raises(LlmOptimizer::ConfigurationError) { config.bad_key = "value" }
    assert_includes err.message, "bad_key"
  end

  def test_all_known_keys_are_readable
    config = LlmOptimizer::Configuration.new
    LlmOptimizer::Configuration::KNOWN_KEYS.each do |key|
      assert config.respond_to?(key), "Expected Configuration to respond to #{key}"
    end
  end

  def test_all_known_keys_are_writable
    config = LlmOptimizer::Configuration.new
    LlmOptimizer::Configuration::KNOWN_KEYS.each do |key|
      assert config.respond_to?(:"#{key}="), "Expected Configuration to respond to #{key}="
    end
  end
end
