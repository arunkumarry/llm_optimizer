# frozen_string_literal: true

require_relative "../test_helper"

class TestInvoker < Minitest::Test
  def test_passes_only_accepted_keywords
    received = nil
    callable = ->(prompt, model:) { received = [prompt, model] }
    LlmOptimizer::Invoker.call(callable, "hi", model: "m1", tools: [1], schema: {})
    assert_equal %w[hi m1], received
  end

  def test_passes_all_keywords_to_keyrest
    received = nil
    callable = ->(_prompt, **kwargs) { received = kwargs }
    LlmOptimizer::Invoker.call(callable, "hi", model: "m1", tools: [1])
    assert_equal({ model: "m1", tools: [1] }, received)
  end

  def test_passes_optional_keywords_when_accepted
    received = nil
    callable = ->(_prompt, model:, tools: nil) { received = { model: model, tools: tools } }
    LlmOptimizer::Invoker.call(callable, "hi", model: "m1", tools: [1], schema: {})
    assert_equal({ model: "m1", tools: [1] }, received)
  end

  def test_works_with_positional_only_callable
    received = nil
    callable = ->(text) { received = text }
    LlmOptimizer::Invoker.call(callable, "hello")
    assert_equal "hello", received
  end

  def test_works_with_call_objects
    obj = Object.new
    obj.define_singleton_method(:call) { |prompt, model:| "#{prompt}-#{model}" }
    result = LlmOptimizer::Invoker.call(obj, "hi", model: "m1", tools: [1])
    assert_equal "hi-m1", result
  end
end

class TestCustomAdapter < Minitest::Test
  def test_chat_receives_messages_and_model
    received = nil
    adapter = LlmOptimizer::Adapters::Custom.new(
      chat: ->(messages, model:) { received = [messages, model] and "ok" }
    )
    messages = [{ role: "user", content: "hi" }]
    adapter.chat(messages, model: "m1", tools: [1])
    assert_equal [messages, "m1"], received
  end

  def test_supports_embedding_only_with_embed_lambda
    without_embed = LlmOptimizer::Adapters::Custom.new(chat: ->(_m, model:) { model })
    with_embed    = LlmOptimizer::Adapters::Custom.new(chat: ->(_m, model:) { model }, embed: ->(_t) { [1.0] })
    refute without_embed.supports_embedding?
    assert with_embed.supports_embedding?
  end

  def test_embed_without_lambda_raises_embedding_error
    adapter = LlmOptimizer::Adapters::Custom.new(chat: ->(_m, model:) { model })
    assert_raises(LlmOptimizer::EmbeddingError) { adapter.embed("text") }
  end
end

class TestLegacyAdapter < Minitest::Test
  def test_single_message_uses_llm_caller_with_prompt_string
    received = nil
    adapter = LlmOptimizer::Adapters::Legacy.new(llm_caller: ->(prompt, model:) { received = [prompt, model] })
    adapter.chat([{ role: "user", content: "hi" }], model: "m1")
    assert_equal %w[hi m1], received
  end

  def test_history_prefers_messages_caller
    received = nil
    adapter = LlmOptimizer::Adapters::Legacy.new(
      llm_caller: ->(_p, model:) { model },
      messages_caller: ->(messages, model:) { received = [messages.length, model] and "ok" }
    )
    adapter.chat([{ role: "user", content: "a" }, { role: "user", content: "b" }], model: "m1")
    assert_equal [2, "m1"], received
  end

  def test_history_without_messages_caller_falls_back_to_llm_caller
    received = nil
    adapter = LlmOptimizer::Adapters::Legacy.new(llm_caller: ->(prompt, model:) { received = [prompt, model] })
    adapter.chat([{ role: "user", content: "a" }, { role: "user", content: "current" }], model: "m1")
    assert_equal %w[current m1], received
  end

  def test_no_llm_caller_raises_configuration_error
    adapter = LlmOptimizer::Adapters::Legacy.new
    assert_raises(LlmOptimizer::ConfigurationError) do
      adapter.chat([{ role: "user", content: "hi" }], model: "m1")
    end
  end

  def test_strict_arity_lambda_does_not_receive_unknown_keywords
    # Regression: 0.1.6 passed tools: unconditionally, crashing lambdas
    # written against the documented ->(prompt, model:) signature.
    adapter = LlmOptimizer::Adapters::Legacy.new(llm_caller: ->(prompt, model:) { "#{prompt}-#{model}" })
    result = adapter.chat([{ role: "user", content: "hi" }], model: "m1", tools: [{ name: "t" }], schema: {})
    assert_equal "hi-m1", result
  end
end

class TestAdapterRegistry < Minitest::Test
  def test_unknown_adapter_raises_with_available_list
    err = assert_raises(LlmOptimizer::ConfigurationError) { LlmOptimizer::Adapters.resolve(:nope) }
    assert_includes err.message, ":ruby_llm"
  end

  unless defined?(::RubyLLM)
    def test_missing_gem_raises_actionable_error
      adapter = LlmOptimizer::Adapters.resolve(:ruby_llm)
      err = assert_raises(LlmOptimizer::ConfigurationError) do
        adapter.chat([{ role: "user", content: "hi" }], model: "m1")
      end
      assert_includes err.message, "ruby_llm"
      assert_includes err.message, "Gemfile"
    end
  end

  def test_anthropic_adapter_does_not_support_embeddings
    adapter = LlmOptimizer::Adapters.resolve(:anthropic)
    refute adapter.supports_embedding?
  end
end
