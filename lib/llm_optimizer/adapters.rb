# frozen_string_literal: true

require_relative "adapters/base"
require_relative "adapters/custom"
require_relative "adapters/legacy"
require_relative "adapters/ruby_llm"
require_relative "adapters/open_ai"
require_relative "adapters/anthropic"

module LlmOptimizer
  module Adapters
    REGISTRY = {
      ruby_llm: "RubyLLM",
      open_ai: "OpenAI",
      openai: "OpenAI",
      anthropic: "Anthropic"
    }.freeze

    def self.resolve(id, **)
      class_name = REGISTRY[id.to_sym]
      unless class_name
        raise ConfigurationError,
              "Unknown adapter #{id.inspect}. Built-in adapters: :ruby_llm, :open_ai, :anthropic. " \
              "For any other provider, pass an adapter instance " \
              "(e.g. LlmOptimizer::Adapters::Custom.new(chat: ->(messages, model:) { ... }))."
      end

      const_get(class_name).new(**)
    end
  end
end
