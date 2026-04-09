# frozen_string_literal: true

require_relative "../test_helper"

class TestModelRouter < Minitest::Test
  def config_with(route_to: :auto)
    cfg = LlmOptimizer::Configuration.new
    cfg.route_to = route_to
    cfg
  end

  def router(route_to: :auto)
    LlmOptimizer::ModelRouter.new(config_with(route_to: route_to))
  end

  # Always returns valid tier

  def test_returns_simple_or_complex_for_any_prompt
    result = router.route("hello world")
    assert_includes %i[simple complex], result
  end

  def test_returns_symbol_not_string
    assert_kind_of Symbol, router.route("hello")
  end

  # Short prompts → :simple

  def test_short_prompt_routes_simple
    assert_equal :simple, router.route("What is Redis?")
  end

  def test_prompt_under_20_words_routes_simple
    prompt = "Tell me about Ruby"
    assert_equal :simple, router.route(prompt)
  end

  def test_prompt_exactly_20_words_routes_complex
    prompt = Array.new(20, "word").join(" ")
    assert_equal :complex, router.route(prompt)
  end

  def test_long_prompt_without_keywords_routes_complex
    prompt = "word " * 25
    assert_equal :complex, router.route(prompt.strip)
  end

  # Complex keywords → :complex

  def test_analyze_keyword_routes_complex
    assert_equal :complex, router.route("Please analyze this code")
  end

  def test_refactor_keyword_routes_complex
    assert_equal :complex, router.route("Can you refactor this?")
  end

  def test_debug_keyword_routes_complex
    assert_equal :complex, router.route("Help me debug this issue")
  end

  def test_architect_keyword_routes_complex
    assert_equal :complex, router.route("architect a new system")
  end

  def test_explain_in_detail_phrase_routes_complex
    assert_equal :complex, router.route("explain in detail how this works")
  end

  def test_keyword_case_insensitive
    assert_equal :complex, router.route("ANALYZE this please")
  end

  # Code blocks → :complex

  def test_backtick_code_block_routes_complex
    assert_equal :complex, router.route("Here is code:\n```\nputs 'hello'\n```")
  end

  def test_tilde_code_block_routes_complex
    assert_equal :complex, router.route("~~~\nsome code\n~~~")
  end

  def test_short_prompt_with_code_block_routes_complex
    assert_equal :complex, router.route("Fix ```x = 1```")
  end

  # Explicit route_to override

  def test_route_to_simple_overrides_complex_prompt
    r = router(route_to: :simple)
    assert_equal :simple, r.route("analyze and refactor this entire complex system architecture")
  end

  def test_route_to_complex_overrides_simple_prompt
    r = router(route_to: :complex)
    assert_equal :complex, r.route("Hi")
  end

  def test_route_to_auto_uses_heuristic
    r = router(route_to: :auto)
    assert_equal :simple, r.route("What time is it?")
  end
end
