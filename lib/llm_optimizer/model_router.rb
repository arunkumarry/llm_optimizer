# frozen_string_literal: true

module LlmOptimizer
  class ModelRouter
    COMPLEX_KEYWORDS = %w[analyze refactor debug architect].freeze
    COMPLEX_PHRASES  = ["explain in detail"].freeze
    CODE_BLOCK_RE    = /```|~~~/

    CLASSIFIER_PROMPT = <<~PROMPT
      Classify the following prompt as either 'simple' or 'complex'.

      Rules:
      - simple: factual questions, basic lookups, short explanations, greetings
      - complex: code generation, debugging, architecture, multi-step reasoning, analysis

      Reply with exactly one word: simple or complex

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
      normalized = response.to_s.strip.downcase.gsub(/[^a-z]/, "")
      return :simple  if normalized == "simple"
      return :complex if normalized == "complex"

      nil # unrecognized response — fall through to heuristic
    rescue StandardError
      nil # classifier failure — fall through to heuristic
    end
  end
end
