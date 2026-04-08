# frozen_string_literal: true

module LlmOptimizer
  OptimizeResult = Struct.new(
    :response, :model, :model_tier, :cache_status,
    :original_tokens, :compressed_tokens, :latency_ms, :messages,
    keyword_init: true
  )
end
