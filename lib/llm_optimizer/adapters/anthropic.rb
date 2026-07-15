# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Adapter for the official anthropic gem (https://rubygems.org/gems/anthropic).
    #
    #   config.adapter = :anthropic   # uses ENV["ANTHROPIC_API_KEY"]
    #   # or with options / your own client:
    #   config.adapter = LlmOptimizer::Adapters::Anthropic.new(api_key: "...", max_tokens: 2048)
    #   config.adapter = LlmOptimizer::Adapters::Anthropic.new(client: $anthropic)
    #
    # Anthropic has no embeddings API, so semantic caching needs a separate
    # config.embedding_caller (e.g. Voyage AI or OpenAI embeddings).
    class Anthropic < Base
      DEFAULT_MAX_TOKENS = 4096

      def initialize(client: nil, api_key: nil, max_tokens: DEFAULT_MAX_TOKENS)
        @client     = client
        @api_key    = api_key
        @max_tokens = max_tokens
        super()
      end

      def chat(messages, model:, tools: nil, schema: nil) # rubocop:disable Lint/UnusedMethodArgument
        system_parts  = messages.select { |m| message_role(m) == "system" }.map { |m| message_content(m) }
        chat_messages = messages.reject { |m| message_role(m) == "system" }
                                .map { |m| { role: message_role(m), content: message_content(m) } }

        parameters = { model: model, max_tokens: @max_tokens, messages: chat_messages }
        parameters[:system] = system_parts.join("\n\n") unless system_parts.empty?
        parameters[:tools]  = tools if tools && !tools.empty?

        response = client.messages.create(**parameters)

        { content: extract_text(response),
          input_tokens: response.usage&.input_tokens,
          output_tokens: response.usage&.output_tokens }
      end

      private

      def extract_text(response)
        response.content
                .select { |block| block.respond_to?(:type) && block.type.to_s == "text" }
                .map(&:text)
                .join
      end

      def client
        @client ||= begin
          require_dependency!("anthropic")
          ::Anthropic::Client.new(api_key: @api_key || ENV.fetch("ANTHROPIC_API_KEY", nil))
        end
      end
    end
  end
end
