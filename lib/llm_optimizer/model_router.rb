# frozen_string_literal: true

module LlmOptimizer
  class ModelRouter
    COMPLEX_KEYWORDS = %w[analyze refactor debug architect].freeze
    COMPLEX_PHRASES  = ["explain in detail"].freeze
    CODE_BLOCK_RE    = /```|~~~/

    CLASSIFIER_PROMPT = <<~PROMPT
      Classify the following prompt as either 'simple' or 'complex'.

      Rules:
      - simple: factual questions, basic lookups, short explanations, greetings, chitchat, general statements, simple mathematical calculations with additions, subtractions, multiplications and divisions
        Example - Hello, Bye, You are funny, how are you?, what is the capital of France, tell me about yourself, what is 2 + 3 - 1 * 10 / 2 etc.
      - complex: code generation, debugging, architecture, multi-step reasoning, analysis
        Example - how does pandas extract my information, debug this code, why is rag apps consume more tokens, give me code to print star in python etc.

      Reply with exactly one word, no punctuation: simple or complex

      Prompt: %<prompt>s
    PROMPT

    def initialize(config)
      @config = config
    end

    def route(prompt)
      # Explicit override — always
      return @config.route_to if %i[simple complex].include?(@config.route_to)

      # Unambiguous fast-path signals (no LLM call needed)
      return :complex if CODE_BLOCK_RE.match?(prompt)

      lower = prompt.downcase
      return :complex if COMPLEX_KEYWORDS.any? { |kw| lower.include?(kw) }
      return :complex if COMPLEX_PHRASES.any?  { |ph| lower.include?(ph) }

      # LLM classifier for ambiguous prompts
      if @config.classifier_caller
        result = classify_with_llm(prompt)
        return result if result
      end

      # Fallback heuristic
      prompt.split.length < 20 ? :simple : :complex
    end

    private

    def classify_with_llm(prompt)
      classifier_prompt = format(CLASSIFIER_PROMPT, prompt: prompt)
      response = @config.classifier_caller.call(classifier_prompt)
      normalized = response.to_s.strip.downcase

      # Check for word boundary match to handle responses like
      # "simple." / "**simple**" / "the answer is simple"
      return :simple  if normalized.match?(/\bsimple\b/)
      return :complex if normalized.match?(/\bcomplex\b/)

      nil # unrecognized response — fall through to heuristic
    rescue StandardError
      nil # classifier failure — fall through to heuristic
    end
  end
end
