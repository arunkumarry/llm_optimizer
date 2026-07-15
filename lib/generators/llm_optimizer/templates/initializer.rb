# frozen_string_literal: true

# LlmOptimizer — run `rails generate llm_optimizer:install` to regenerate.
# Docs: https://github.com/arunkumarry/llm_optimizer

LlmOptimizer.configure do |config|
  # 1. Adapter — how the gem talks to your LLM provider.
  #    Built-in: :ruby_llm (recommended, covers OpenAI/Anthropic/Gemini/Bedrock/
  #    Ollama via the ruby_llm gem), :open_ai (ruby-openai gem), :anthropic.
  #    Any other provider: see "Custom adapter" in the appendix below.
  config.adapter = :ruby_llm

  # 2. Models — cheap tier for simple prompts, premium tier for complex ones.
  config.routing.simple_model  = "gpt-4o-mini"
  config.routing.complex_model = "claude-sonnet-4-5"

  # 3. Optimizations — all off by default; enable what you need.
  config.cache.enabled       = false # semantic cache (needs redis_url)
  config.compression.enabled = false # stop-word pruning before the LLM call
  config.history.enabled     = false # summarize old conversation messages

  # Required when cache.enabled or conversation_id is used:
  # config.redis_url = ENV["REDIS_URL"]

  config.logger = Rails.logger
end

# Fails fast at boot with an actionable message if anything is missing:
LlmOptimizer.validate!

# ---------------------------------------------------------------------------
# Appendix — advanced options
# ---------------------------------------------------------------------------
#
# Custom adapter (any provider — you supply the lambdas):
#
#   config.adapter = LlmOptimizer::Adapters::Custom.new(
#     chat:  ->(messages, model:, tools: nil) {
#       # messages is an Array of { role:, content: } hashes.
#       # Return a String, or { content:, input_tokens:, output_tokens: }.
#       MyLlmService.chat(messages, model: model)
#     },
#     embed: ->(text) { MyEmbeddingService.embed(text) } # needed for the cache
#   )
#
# Adapter with options (instead of the symbol shorthand):
#
#   config.adapter = LlmOptimizer::Adapters::OpenAI.new(
#     access_token: Rails.application.credentials.openai_api_key,
#     embedding_model: "text-embedding-3-large"
#   )
#
# Routing:
#
#   config.routing.mode             = :auto         # :auto | :simple | :complex
#   config.routing.classifier_model = "gpt-4o-mini" # LLM-classify ambiguous
#                                                   # prompts (default: word-count
#                                                   # heuristic, no LLM call)
#
# Semantic cache tuning:
#
#   config.cache.threshold = 0.96    # cosine similarity cutoff for a hit
#   config.cache.ttl       = 86_400  # seconds
#   config.cache.scope     = nil     # namespace hits (e.g. per user/tenant)
#
# Conversations (LlmOptimizer.optimize(prompt, conversation_id: "abc")):
#
#   config.conversation.system_prompt = "You are a helpful assistant."
#   config.conversation.ttl           = 86_400 # 0 = no expiry
#
# History summarization:
#
#   config.history.token_budget = 4000 # summarize once history exceeds this
#
# Tools / structured output (passed through to the adapter):
#
#   config.tools  = [ ... ]  # provider-format tool definitions
#   config.schema = { ... }  # JSON schema for structured output
#
# Debugging:
#
#   config.debug_logging = Rails.env.development? # logs full prompt + response
