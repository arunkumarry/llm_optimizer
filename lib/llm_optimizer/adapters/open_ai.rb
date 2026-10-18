# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Adapter for the official OpenAI Ruby SDK
    # (https://github.com/openai/openai-ruby, `gem "openai"`).
    #
    #   config.adapter = :open_ai   # uses ENV["OPENAI_API_KEY"]
    #   # or with options / your own client:
    #   config.adapter = LlmOptimizer::Adapters::OpenAI.new(
    #     api_key: Rails.application.credentials.openai_api_key,
    #     embedding_model: "text-embedding-3-large"
    #   )
    #   config.adapter = LlmOptimizer::Adapters::OpenAI.new(client: $openai)
    #
    # Note: this targets the official `openai` gem, not the community
    # `ruby-openai` gem — they share the OpenAI::Client constant but have
    # different APIs (api_key: vs access_token:, chat.completions.create vs
    # chat(parameters:)). If you use ruby-openai, wrap it in Adapters::Custom.
    class OpenAI < Base
      DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small"

      def initialize(client: nil, api_key: nil, embedding_model: nil, **client_options)
        @client          = client
        @api_key         = api_key
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

        response = client.chat.completions.create(**parameters)
        choice   = response.choices.first

        { content: choice.message.content,
          input_tokens: response.usage&.prompt_tokens,
          output_tokens: response.usage&.completion_tokens }
      end

      def embed(text)
        response = client.embeddings.create(model: @embedding_model, input: text)
        response.data.first.embedding
      end

      def supports_embedding?
        true
      end

      private

      def client
        @client ||= begin
          require_dependency!("openai")
          options = @client_options.dup
          options[:api_key] = @api_key || ENV.fetch("OPENAI_API_KEY", nil)
          ::OpenAI::Client.new(**options)
        end
      end
    end
  end
end
