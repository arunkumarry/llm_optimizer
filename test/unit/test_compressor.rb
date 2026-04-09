# frozen_string_literal: true

require_relative "../test_helper"

class TestCompressor < Minitest::Test
  def setup
    @compressor = LlmOptimizer::Compressor.new
  end

  # Stop word removal

  def test_removes_stop_words
    result = @compressor.compress("the cat sat on the mat")
    refute_includes result.split, "the"
    refute_includes result.split, "on"
  end

  def test_preserves_non_stop_words
    result = @compressor.compress("the quick brown fox")
    assert_includes result.split, "quick"
    assert_includes result.split, "brown"
    assert_includes result.split, "fox"
  end

  def test_preserves_word_order
    result = @compressor.compress("the quick brown fox jumps")
    words = result.split
    assert_equal(words, words.sort_by { |w| result.index(w) })
    assert_equal "quick brown fox jumps", result
  end

  def test_stop_word_removal_is_case_insensitive
    result = @compressor.compress("The cat IS fast")
    refute_includes result.split, "The"
    refute_includes result.split, "IS"
  end

  def test_empty_string_returns_empty
    assert_equal "", @compressor.compress("")
  end

  def test_all_stop_words_returns_empty
    assert_equal "", @compressor.compress("the a an is are")
  end

  # Whitespace normalization

  def test_collapses_multiple_spaces
    result = @compressor.compress("hello   world")
    refute_match(/\s{2,}/, result)
  end

  def test_strips_leading_trailing_whitespace
    result = @compressor.compress("  hello world  ")
    assert_equal result, result.strip
  end

  def test_collapses_tabs_and_newlines
    result = @compressor.compress("hello\t\nworld")
    refute_match(/\s{2,}/, result)
  end

  # Code block preservation

  def test_preserves_code_block_content
    prompt = "Here is code:\n```\nthe = 1\na = 2\n```\nend"
    result = @compressor.compress(prompt)
    assert_includes result, "the = 1"
    assert_includes result, "a = 2"
  end

  def test_does_not_remove_stop_words_inside_code_block
    prompt = "```\nthe_variable = is_valid\n```"
    result = @compressor.compress(prompt)
    assert_includes result, "the_variable = is_valid"
  end

  def test_removes_stop_words_outside_code_block
    prompt = "the code is:\n```\nx = 1\n```\nand the result"
    result = @compressor.compress(prompt)
    refute_match(/\bthe\b/, result.split("```").first)
  end

  def test_preserves_tilde_code_block
    prompt = "~~~\nthe = 1\n~~~"
    result = @compressor.compress(prompt)
    assert_includes result, "the = 1"
  end

  # Token estimation

  def test_estimate_tokens_empty_string
    assert_equal 0, @compressor.estimate_tokens("")
  end

  def test_estimate_tokens_four_chars
    assert_equal 1, @compressor.estimate_tokens("abcd")
  end

  def test_estimate_tokens_rounds_up
    assert_equal 2, @compressor.estimate_tokens("abcde")
  end

  def test_estimate_tokens_formula
    text = "a" * 100
    assert_equal 25, @compressor.estimate_tokens(text)
  end

  def test_compression_reduces_token_count
    prompt = "the quick brown fox is jumping over the lazy dog in the field"
    original = @compressor.estimate_tokens(prompt)
    compressed = @compressor.estimate_tokens(@compressor.compress(prompt))
    assert compressed < original
  end
end
