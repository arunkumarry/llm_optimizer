# frozen_string_literal: true

require_relative "../test_helper"

class TestHistoryManager < Minitest::Test
  SUMMARY = "Summary of conversation"

  def stub_llm_caller(response = SUMMARY)
    ->(prompt, model:) { response }
  end

  def failing_llm_caller
    ->(prompt, model:) { raise "LLM unavailable" }
  end

  def manager(budget: 100, caller: stub_llm_caller)
    LlmOptimizer::HistoryManager.new(
      llm_caller:   caller,
      simple_model: "gpt-4o-mini",
      token_budget: budget
    )
  end

  def messages(count, chars_each: 10)
    count.times.map { |i| { role: "user", content: "x" * chars_each } }
  end

  # estimate_tokens

  def test_estimate_tokens_empty
    assert_equal 0, manager.estimate_tokens([])
  end

  def test_estimate_tokens_single_message
    msgs = [{ role: "user", content: "abcd" }]
    assert_equal 1, manager.estimate_tokens(msgs)
  end

  def test_estimate_tokens_multiple_messages
    msgs = [
      { role: "user",      content: "a" * 8 },
      { role: "assistant", content: "b" * 8 }
    ]
    assert_equal 4, manager.estimate_tokens(msgs)
  end

  def test_estimate_tokens_uses_integer_division
    msgs = [{ role: "user", content: "abcde" }]  # 5 chars / 4 = 1
    assert_equal 1, manager.estimate_tokens(msgs)
  end

  def test_estimate_tokens_supports_string_keys
    msgs = [{ "role" => "user", "content" => "abcd" }]
    assert_equal 1, manager.estimate_tokens(msgs)
  end

  # process: under budget

  def test_process_returns_messages_unchanged_when_under_budget
    msgs = messages(3, chars_each: 10)
    result = manager(budget: 1000).process(msgs)
    assert_equal msgs, result
  end

  def test_process_returns_same_object_when_under_budget
    msgs = messages(2, chars_each: 4)
    result = manager(budget: 1000).process(msgs)
    assert_same msgs, result
  end

  # process: over budget

  def test_process_summarizes_when_over_budget
    msgs = messages(15, chars_each: 100)  # 15 * 100 / 4 = 375 > 10 budget
    result = manager(budget: 10).process(msgs)
    assert_equal "system", result.first[:role]
    assert_equal SUMMARY, result.first[:content]
  end

  def test_process_replaces_oldest_10_messages
    msgs = messages(15, chars_each: 100)
    result = manager(budget: 10).process(msgs)
    # 1 summary + 5 remaining = 6
    assert_equal 6, result.length
  end

  def test_process_replaces_all_when_fewer_than_10
    msgs = messages(5, chars_each: 100)
    result = manager(budget: 10).process(msgs)
    assert_equal 1, result.length
    assert_equal "system", result.first[:role]
  end

  def test_process_preserves_messages_after_summarized_block
    msgs = 15.times.map { |i| { role: "user", content: "x" * 100 } }
    result = manager(budget: 10).process(msgs)
    assert_equal msgs.last(5), result.last(5)
  end

  def test_process_summary_message_has_system_role
    msgs = messages(12, chars_each: 100)
    result = manager(budget: 10).process(msgs)
    assert_equal "system", result.first[:role]
  end

  # process: LLM failure fallback

  def test_process_returns_original_on_llm_failure
    msgs = messages(15, chars_each: 100)
    result = manager(budget: 10, caller: failing_llm_caller).process(msgs)
    assert_equal msgs, result
  end

  def test_process_does_not_raise_on_llm_failure
    msgs = messages(15, chars_each: 100)
    # Should not raise even when LLM fails
    result = manager(budget: 10, caller: failing_llm_caller).process(msgs)
    assert_equal msgs, result
  end
end
