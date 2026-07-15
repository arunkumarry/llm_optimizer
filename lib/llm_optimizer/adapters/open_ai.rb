# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Adapter for the ruby-openai gem (https://rubygems.org/gems/ruby-openai).
    #
    #   config.adapter = :open_ai   # uses ENV["OPENAI_API_KEY"]
    #   # or with options / your own client:
    #   config.adapter = LlmOptimizer::Adapters::OpenAI.new(
    #     access_token: Rails.application.credentials.openai_api_key,
    #     embedding_model: "text-embedding-3-large"
    #   )
    #   config.adapter = LlmOptimizer::Adapters::OpenAI.new(client: $openai)
    class OpenAI < Base
      DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small"

      def initialize(client: nil, access_token: nil, embedding_model: nil, **client_options)
        @client          = client
        @access_token    = access_token
        @client_options  = client_options
        @embedding_model = embedding_model || DEFAULT_EMBEDDING_MODEL
        super()
      end

      def chat(messages, model:, tools: nil, schema: nil)
        parameters = {
          model: model,
          messages: messages.map { |m| { role: message_role(m), content: message_content(m) } }
        }
        parameters[:tools] = tools if tools && !tools.empty?
        parameters[:response_format] = { type: "json_schema", json_schema: schema } if schema

        response = client.chat(parameters: parameters)

        { content: response.dig("choices", 0, "message", "content"),
          input_tokens: response.dig("usage", "prompt_tokens"),
          output_tokens: response.dig("usage", "completion_tokens") }
      end

      def embed(text)
        response = client.embeddings(parameters: { model: @embedding_model, input: text })
        response.dig("data", 0, "embedding")
      end

      def supports_embedding?
        true
      end

      private

      def client
        @client ||= begin
          require_dependency!("ruby-openai", "openai")
          options = @client_options.dup
          options[:access_token] = @access_token || ENV.fetch("OPENAI_API_KEY", nil)
          ::OpenAI::Client.new(**options)
        end
      end
    end
  end
end
