# frozen_string_literal: true

module LlmOptimizer
  class OptimizeResult
    attr_accessor :response, :model, :model_tier, :cache_status,
                  :original_tokens, :compressed_tokens, :input_tokens,
                  :output_tokens, :cached_tokens, :latency_ms, :messages

    # rubocop:disable Metrics/ParameterLists
    def initialize(response: nil, model: nil, model_tier: nil, cache_status: nil,
                   original_tokens: 0, compressed_tokens: 0, input_tokens: 0,
                   output_tokens: 0, cached_tokens: 0, latency_ms: 0, messages: [])
      @response = response
      @model = model
      @model_tier = model_tier
      @cache_status = cache_status
      @original_tokens = original_tokens
      @compressed_tokens = compressed_tokens
      @input_tokens = input_tokens
      @output_tokens = output_tokens
      @cached_tokens = cached_tokens
      @latency_ms = latency_ms
      @messages = messages
    end
    # rubocop:enable Metrics/ParameterLists

    def to_h
      {
        response: @response,
        model: @model,
        model_tier: @model_tier,
        cache_status: @cache_status,
        original_tokens: @original_tokens,
        compressed_tokens: @compressed_tokens,
        input_tokens: @input_tokens,
        output_tokens: @output_tokens,
        cached_tokens: @cached_tokens,
        latency_ms: @latency_ms,
        messages: @messages
      }
    end
  end
end
