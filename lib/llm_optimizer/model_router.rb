# frozen_string_literal: true

module LlmOptimizer
  class ModelRouter
    COMPLEX_KEYWORDS = %w[analyze refactor debug architect].freeze
    COMPLEX_PHRASES  = ["explain in detail"].freeze
    CODE_BLOCK_RE    = /```|~~~/

    def initialize(config)
      @config = config
    end

    def route(prompt)
      # explicit override
      return @config.route_to if %i[simple complex].include?(@config.route_to)

      # fenced code block
      return :complex if CODE_BLOCK_RE.match?(prompt)

      # complex keywords or phrases
      lower = prompt.downcase
      return :complex if COMPLEX_KEYWORDS.any? { |kw| lower.include?(kw) }
      return :complex if COMPLEX_PHRASES.any? { |ph| lower.include?(ph) }

      # short prompt
      return :simple if prompt.split.length < 20

      # default
      :complex
    end
  end
end
