# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Adapter for the ruby_llm gem (https://rubygems.org/gems/ruby_llm).
    # Covers OpenAI, Anthropic, Gemini, Bedrock, Ollama and more through a
    # single dependency — the recommended default.
    #
    #   config.adapter = :ruby_llm
    #   # or with options:
    #   config.adapter = LlmOptimizer::Adapters::RubyLLM.new(
    #     provider: :bedrock, assume_model_exists: true,
    #     embedding_model: "text-embedding-3-small"
    #   )
    class RubyLLM < Base
      def initialize(provider: nil, assume_model_exists: nil, embedding_model: nil)
        @provider            = provider
        @assume_model_exists = assume_model_exists
        @embedding_model     = embedding_model
        super()
      end

      def chat(messages, model:, tools: nil, schema: nil)
        require_dependency!("ruby_llm")

        chat = ::RubyLLM.chat(**chat_options(model))
        chat = chat.with_tools(*tools) if tools && !tools.empty?
        chat = chat.with_schema(schema) if schema

        *history, current = messages
        history.each { |m| chat.add_message(role: message_role(m).to_sym, content: message_content(m)) }
        response = chat.ask(message_content(current))

        { content: response.content,
          input_tokens: response.respond_to?(:input_tokens) ? response.input_tokens : nil,
          output_tokens: response.respond_to?(:output_tokens) ? response.output_tokens : nil }
      end

      def embed(text)
        require_dependency!("ruby_llm")

        options = {}
        options[:model] = @embedding_model if @embedding_model
        ::RubyLLM.embed(text, **options).vectors
      end

      def supports_embedding?
        true
      end

      private

      def chat_options(model)
        options = {}
        options[:model]               = model if model
        options[:provider]            = @provider if @provider
        options[:assume_model_exists] = @assume_model_exists unless @assume_model_exists.nil?
        options
      end
    end
  end
end
