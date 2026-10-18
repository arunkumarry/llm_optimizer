# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Escape hatch for providers without a built-in adapter. Wraps plain
    # lambdas and invokes them defensively — only the keyword arguments a
    # lambda's signature accepts are passed, so a simple
    # ->(messages, model:) { ... } works fine.
    #
    #   config.adapter = LlmOptimizer::Adapters::Custom.new(
    #     chat:  ->(messages, model:, tools: nil, schema: nil) { ... }, # -> String or {content:, ...}
    #     embed: ->(text) { ... }                                       # -> Array<Float> (optional)
    #   )
    class Custom < Base
      def initialize(chat:, embed: nil)
        @chat  = chat
        @embed = embed
        super()
      end

      def chat(messages, model:, tools: nil, schema: nil)
        Invoker.call(@chat, messages, model: model, tools: tools, schema: schema)
      end

      def embed(text)
        return super unless @embed

        Invoker.call(@embed, text)
      end

      def supports_embedding?
        !@embed.nil?
      end
    end
  end
end
