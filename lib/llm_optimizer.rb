# frozen_string_literal: true

require_relative "llm_optimizer/version"
require_relative "llm_optimizer/configuration"
require_relative "llm_optimizer/optimize_result"
require_relative "llm_optimizer/compressor"
require_relative "llm_optimizer/model_router"
require_relative "llm_optimizer/embedding_client"
require_relative "llm_optimizer/semantic_cache"
require_relative "llm_optimizer/history_manager"
require_relative "llm_optimizer/conversation_store"
require_relative "llm_optimizer/pipeline"

require "llm_optimizer/railtie" if defined?(Rails)

module LlmOptimizer
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class EmbeddingError < Error; end
  class TimeoutError < Error; end

  @configuration = nil

  extend Pipeline

  def self.configure
    temp = Configuration.new
    yield temp
    configuration.merge!(temp)
    validate_configuration!(configuration)
  end

  def self.validate_configuration!(config)
    return unless config.use_semantic_cache && config.embedding_caller.nil?

    config.logger.warn(
      "[llm_optimizer] use_semantic_cache is true but no embedding_caller is configured. " \
      "Semantic caching will be skipped. Set config.embedding_caller to enable it."
    )
    config.use_semantic_cache = false
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end

  def self.clear_conversation(conversation_id)
    raise ConfigurationError, "redis_url must be configured to use clear_conversation" unless configuration.redis_url

    redis   = build_redis(configuration.redis_url)
    key     = "#{ConversationStore::KEY_NAMESPACE}#{conversation_id}"
    deleted = redis.del(key)
    deleted.positive?
  rescue ::Redis::BaseError => e
    raise LlmOptimizer::Error, "Redis error in clear_conversation: #{e.message}"
  end

  module WrapperModule
    def chat(params, &)
      config = LlmOptimizer.configuration
      prompt = params[:messages] || params[:prompt]
      result = LlmOptimizer.optimize_pre_call(prompt, config)
      return result[:response] if result[:cache_status] == :hit

      optimized_params = params.merge(model: result[:model])
      if params[:messages]
        optimized_params = optimized_params.merge(messages: result[:prompt])
      elsif params[:prompt]
        optimized_params = optimized_params.merge(prompt: result[:prompt])
      end

      response = super(optimized_params, &)
      LlmOptimizer.optimize_post_call(result, response, config)
      response
    end
  end

  def self.wrap_client(client_class)
    return if client_class.ancestors.include?(WrapperModule)

    client_class.prepend(WrapperModule)
  end

  def self.optimize(prompt, options = {}, &)
    start           = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    call_config     = build_call_config(options, &)
    conversation_id = options[:conversation_id]
    validate_conversation_options!(conversation_id, options, call_config)

    original_prompt           = prompt
    original_tokens           = Compressor.new.estimate_tokens(prompt)
    prompt, compressed_tokens = compress(prompt, call_config)
    model_tier, model         = route(prompt, call_config)

    embedding, cached_result = semantic_cache_lookup(prompt, model, model_tier,
                                                     original_tokens, compressed_tokens,
                                                     original_prompt, start, call_config)
    return cached_result if cached_result

    messages, store = load_conversation(conversation_id, options, call_config)
    messages        = apply_history_manager(messages, call_config)
    response, token_info = raw_llm_call(prompt, messages: messages, model: model, config: call_config)
    messages = persist_conversation(store, conversation_id, messages, prompt, response)
    store_in_cache(embedding, response, call_config, token_info)

    latency_ms = elapsed_ms(start)
    emit_log(call_config.logger, call_config,
             cache_status: :miss, model_tier: model_tier,
             original_tokens: original_tokens, compressed_tokens: compressed_tokens,
             latency_ms: latency_ms, prompt: original_prompt, response: response)

    build_result(response, model, model_tier, :miss, original_tokens, compressed_tokens,
                 latency_ms, messages, token_info)
  rescue EmbeddingError => e
    configuration.logger.warn("[llm_optimizer] EmbeddingError (outer rescue): #{e.message}")
    fallback_result(original_prompt, original_tokens, options, start)
  rescue ConfigurationError
    raise
  rescue LlmOptimizer::Error, StandardError => e
    configuration.logger.error("[llm_optimizer] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    fallback_result(original_prompt, original_tokens, options, start)
  end

  def self.optimize_pre_call(prompt, config = configuration)
    prompt     = Compressor.new.compress(prompt) if config.compress_prompt
    model_tier = ModelRouter.new(config).route(prompt)
    model      = model_tier == :simple ? config.simple_model : config.complex_model

    unless config.use_semantic_cache && config.redis_url
      return { prompt: prompt, model: model, model_tier: model_tier,
               embedding: nil, cache_status: :miss, response: nil }
    end

    embedding, result = semantic_cache_lookup(prompt, model, model_tier, nil, nil,
                                              prompt, Process.clock_gettime(Process::CLOCK_MONOTONIC), config)
    if result
      return { prompt: prompt, model: model, model_tier: model_tier,
               embedding: embedding, cache_status: :hit, response: result.response }
    end

    { prompt: prompt, model: model, model_tier: model_tier,
      embedding: embedding, cache_status: :miss, response: nil }
  end

  def self.optimize_post_call(pre_call_result, response, config = configuration)
    store_in_cache(pre_call_result[:embedding], response, config)
  end
end
