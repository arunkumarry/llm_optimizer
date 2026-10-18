# frozen_string_literal: true

module LlmOptimizer
  module Adapters
    # Interface every adapter implements.
    #
    #   chat(messages, model:, tools: nil, schema: nil)
    #     messages — Array of { role:, content: } hashes
    #                (roles: "system", "user", "assistant")
    #     returns  — String, or a Hash with :content plus optional
    #                :input_tokens, :output_tokens, :cached_tokens
    #
    #   embed(text)
    #     returns  — Array<Float> embedding vector
    #                (only required when supports_embedding? is true)
    class Base
      def chat(_messages, model:, tools: nil, schema: nil)
        raise NotImplementedError, "#{self.class} must implement #chat"
      end

      def embed(_text)
        raise EmbeddingError,
              "#{self.class} does not support embeddings. Use an adapter that does, " \
              "or set config.embedding_caller = ->(text) { ... }."
      end

      def supports_embedding?
        false
      end

      private

      def require_dependency!(gem_name, require_path = gem_name)
        require require_path
      rescue LoadError
        raise ConfigurationError,
              "The #{self.class.name.split("::").last} adapter needs the #{gem_name} gem. " \
              "Add `gem \"#{gem_name}\"` to your Gemfile and run `bundle install`."
      end

      def message_role(message)
        (message[:role] || message["role"]).to_s
      end

      def message_content(message)
        message[:content] || message["content"]
      end
    end
  end
end
