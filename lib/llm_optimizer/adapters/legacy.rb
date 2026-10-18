# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Internal adapter built automatically from the deprecated 0.1.x caller
    # lambdas (llm_caller / messages_caller / embedding_caller) so old
    # initializers keep working. Prefer config.adapter going forward.
    class Legacy < Base
      def initialize(llm_caller: nil, messages_caller: nil, embedding_caller: nil)
        @llm_caller       = llm_caller
        @messages_caller  = messages_caller
        @embedding_caller = embedding_caller
        super()
      end

      def chat(messages, model:, tools: nil, schema: nil)
        if @messages_caller && messages.length > 1
          Invoker.call(@messages_caller, messages, model: model, tools: tools, schema: schema)
        else
          unless @llm_caller
            raise ConfigurationError,
                  "No llm_caller configured. Set config.adapter (e.g. :ruby_llm) or config.llm_caller."
          end

          Invoker.call(@llm_caller, message_content(messages.last), model: model, tools: tools, schema: schema)
        end
      end

      def embed(text)
        return super unless @embedding_caller

        Invoker.call(@embedding_caller, text)
      end

      def supports_embedding?
        !@embedding_caller.nil?
      end
    end
  end
end
