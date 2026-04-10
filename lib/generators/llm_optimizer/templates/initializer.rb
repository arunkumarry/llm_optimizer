# frozen_string_literal: true

# LlmOptimizer initializer
# Run `rails generate llm_optimizer:install` to regenerate this file.
#
# Docs: https://github.com/arunkumar/llm_optimizer

LlmOptimizer.configure do |config|
  # --- Feature flags ---
  # All optimizations are off by default. Enable what you need.
  config.compress_prompt    = false  # strip stop words before sending to LLM
  config.use_semantic_cache = false  # cache responses by vector similarity in Redis
  config.manage_history     = false  # summarize old messages when over token budget

  # --- Model routing ---
  # :auto classifies each prompt; :simple or :complex forces a tier
  config.route_to      = :auto
  config.simple_model  = "gpt-4o-mini"
  config.complex_model = "gpt-4o"

  # --- Redis (required only if use_semantic_cache: true) ---
  config.redis_url = ENV.fetch("REDIS_URL", nil)

  # --- Tuning ---
  config.similarity_threshold = 0.96   # cosine similarity cutoff for a cache hit
  config.token_budget         = 4000   # token limit before history summarization kicks in
  config.cache_ttl            = 86_400 # cache entry TTL in seconds (default: 24h)
  config.timeout_seconds      = 5 # timeout for embedding / external API calls

  # --- Logging ---
  config.logger        = Rails.logger
  config.debug_logging = Rails.env.development?

  # --- LLM caller (required) ---
  # Wire this up to however your app already calls the LLM.
  #
  # Example with ruby-openai:
  #   config.llm_caller = ->(prompt, model:) {
  #     OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  #       .chat(parameters: { model: model, messages: [{ role: "user", content: prompt }] })
  #       .dig("choices", 0, "message", "content")
  #   }
  #
  # Example with a shared service object:
  #   config.llm_caller = ->(prompt, model:) {
  #     provider = if model.include?("claude") then :anthropic
  #              elsif model.include?("gpt") then :openai
  #              elsif model.include?("gemini") then :gemini
  #              elsif model.include?("nova") || model.include?("amazon") then :bedrock
  #              else :ollama
  #              end
  #     RubyLLM.chat(model: model, provider: provider, assume_model_exists: true) }
  #   end
  #
  config.llm_caller = lambda { |_prompt, **_kwargs|
    raise NotImplementedError, "[llm_optimizer] llm_caller is not configured. " \
                               "Edit config/initializers/llm_optimizer.rb and wire it to your LLM client."
  }

  # --- Embeddings caller (optional) ---
  # Only needed if use_semantic_cache: true.
  # If omitted, falls back to OpenAI via ENV["OPENAI_API_KEY"].
  #
  # Example:
  #   config.embedding_caller = ->(text) { EmbeddingService.embed(text) }
  #
  # --- Routing classifier (optional) ---
  # When set, ambiguous prompts are classified by a cheap LLM instead of
  # falling back to the word-count heuristic. Unambiguous signals (code blocks,
  # keywords) still bypass the classifier for speed.
  #
  # Example:
  #   config.classifier_caller = ->(prompt) {
  #     RubyLLM.chat(model: "amazon.nova-micro-v1:0", assume_model_exists: true)
  #       .ask(prompt).content.strip.downcase
  #   }
  #
  # config.classifier_caller = nil
end
