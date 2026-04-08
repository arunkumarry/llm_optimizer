# frozen_string_literal: true

require_relative "llm_optimizer/version"
require_relative "llm_optimizer/configuration"
require_relative "llm_optimizer/optimize_result"
require_relative "llm_optimizer/compressor"
require_relative "llm_optimizer/model_router"
require_relative "llm_optimizer/embedding_client"
require_relative "llm_optimizer/semantic_cache"
require_relative "llm_optimizer/history_manager"

module LlmOptimizer
  # Base error class for all gem-specific exceptions
  class Error < StandardError; end

  # Raised when an unrecognized configuration key is set
  class ConfigurationError < Error; end

  # Raised when the embedding API call fails
  class EmbeddingError < Error; end

  # Raised when a network timeout is exceeded
  class TimeoutError < Error; end

  # Global configuration
  @configuration = nil

  # Yields a Configuration instance; merges it into the global config.
  def self.configure
    temp = Configuration.new
    yield temp
    configuration.merge!(temp)
    validate_configuration!(configuration)
  end

  # Warns about misconfigured options rather than failing silently at call time.
  def self.validate_configuration!(config)
    if config.use_semantic_cache && config.embedding_caller.nil?
      config.logger.warn(
        "[llm_optimizer] use_semantic_cache is true but no embedding_caller is configured. " \
        "Semantic caching will be skipped. Set config.embedding_caller to enable it."
      )
      config.use_semantic_cache = false
    end

    if config.llm_caller.nil?
      config.logger.warn(
        "[llm_optimizer] No llm_caller configured. " \
        "LlmOptimizer.optimize will raise ConfigurationError unless llm_caller is set."
      )
    end
  end

  # Returns the current global Configuration, lazy-initializing if nil.
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Replaces the global config with a fresh default Configuration.
  # Useful in tests to avoid state leakage.
  def self.reset_configuration!
    @configuration = Configuration.new
  end

  # Opt-in client wrapping
  module WrapperModule
    def chat(params, &block)
      prompt = params[:messages] || params[:prompt]
      optimized = LlmOptimizer.optimize(prompt)
      params = params.merge(messages: optimized.messages, model: optimized.model)
      super(params, &block)
    end
  end

  # Prepends WrapperModule into client_class; idempotent — safe to call N times.
  def self.wrap_client(client_class)
    return if client_class.ancestors.include?(WrapperModule)

    client_class.prepend(WrapperModule)
  end

  # Primary entry point
  # Runs the optimization pipeline and returns an OptimizeResult.

  # options hash keys mirror Configuration attr_accessors and are merged over
  # the global config for this call only.  An optional block is yielded a
  # per-call Configuration for fine-grained control.
  def self.optimize(prompt, options = {}, &block)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Resolve per-call configuration 
    call_config = Configuration.new
    call_config.merge!(configuration)
    options.each { |k, v| call_config.public_send(:"#{k}=", v) }
    yield call_config if block_given?

    logger = call_config.logger

    # Keep a reference to the original prompt for fallback use
    original_prompt = prompt

    # Compression
    compressor      = Compressor.new
    original_tokens = compressor.estimate_tokens(prompt)
    compressed_tokens = nil

    if call_config.compress_prompt
      prompt            = compressor.compress(prompt)
      compressed_tokens = compressor.estimate_tokens(prompt)
    end

    # Model routing
    router     = ModelRouter.new(call_config)
    model_tier = router.route(prompt)
    model      = model_tier == :simple ? call_config.simple_model : call_config.complex_model

    # Semantic cache lookup
    embedding = nil

    if call_config.use_semantic_cache
      begin
        emb_client = EmbeddingClient.new(
          model:            call_config.embedding_model,
          timeout_seconds:  call_config.timeout_seconds,
          embedding_caller: call_config.embedding_caller
        )
        embedding = emb_client.embed(prompt)

        if call_config.redis_url
          redis  = build_redis(call_config.redis_url)
          cache  = SemanticCache.new(redis, threshold: call_config.similarity_threshold, ttl: call_config.cache_ttl)
          cached = cache.lookup(embedding)

          if cached
            latency_ms = elapsed_ms(start)
            emit_log(logger, call_config,
                     cache_status: :hit, model_tier: model_tier,
                     original_tokens: original_tokens, compressed_tokens: compressed_tokens,
                     latency_ms: latency_ms, prompt: original_prompt, response: cached)
            return OptimizeResult.new(
              response:          cached,
              model:             model,
              model_tier:        model_tier,
              cache_status:      :hit,
              original_tokens:   original_tokens,
              compressed_tokens: compressed_tokens,
              latency_ms:        latency_ms,
              messages:          options[:messages]
            )
          end
        end
      rescue EmbeddingError => e
        logger.warn("[llm_optimizer] EmbeddingError (treating as cache miss): #{e.message}")
        embedding = nil
        # continue pipeline as cache miss
      end
    end

    # History management
    messages = options[:messages]
    if call_config.manage_history && messages
      llm_caller = ->(p, model:) { raw_llm_call(p, model: model) }
      history_mgr = HistoryManager.new(
        llm_caller:   llm_caller,
        simple_model: call_config.simple_model,
        token_budget: call_config.token_budget
      )
      messages = history_mgr.process(messages)
    end

    # Raw LLM call
    response = raw_llm_call(prompt, model: model, config: call_config)

    # Cache store
    if call_config.use_semantic_cache && embedding && call_config.redis_url
      begin
        redis = build_redis(call_config.redis_url)
        cache = SemanticCache.new(redis, threshold: call_config.similarity_threshold, ttl: call_config.cache_ttl)
        cache.store(embedding, response)
      rescue StandardError => e
        logger.warn("[llm_optimizer] SemanticCache store failed: #{e.message}")
      end
    end

    # Build result
    latency_ms = elapsed_ms(start)
    emit_log(logger, call_config,
             cache_status: :miss, model_tier: model_tier,
             original_tokens: original_tokens, compressed_tokens: compressed_tokens,
             latency_ms: latency_ms, prompt: original_prompt, response: response)

    OptimizeResult.new(
      response:          response,
      model:             model,
      model_tier:        model_tier,
      cache_status:      :miss,
      original_tokens:   original_tokens,
      compressed_tokens: compressed_tokens,
      latency_ms:        latency_ms,
      messages:          messages
    )

  rescue EmbeddingError => e
    # Treat embedding failures as cache miss — continue to raw LLM call
    logger = configuration.logger
    logger.warn("[llm_optimizer] EmbeddingError (outer rescue, treating as cache miss): #{e.message}")
    latency_ms = elapsed_ms(start)
    response   = raw_llm_call(original_prompt, model: nil, config: configuration)
    OptimizeResult.new(
      response:          response,
      model:             nil,
      model_tier:        nil,
      cache_status:      :miss,
      original_tokens:   original_tokens || 0,
      compressed_tokens: nil,
      latency_ms:        latency_ms,
      messages:          options[:messages]
    )

  rescue LlmOptimizer::Error, StandardError => e
    logger = configuration.logger
    logger.error("[llm_optimizer] #{e.class}: #{e.message}")
    latency_ms = elapsed_ms(start)
    response   = raw_llm_call(original_prompt, model: nil, config: configuration)
    OptimizeResult.new(
      response:          response,
      model:             nil,
      model_tier:        nil,
      cache_status:      :miss,
      original_tokens:   original_tokens || 0,
      compressed_tokens: nil,
      latency_ms:        latency_ms,
      messages:          options[:messages]
    )
  end

  # Private helpers

  class << self
    private

    def raw_llm_call(prompt, model:, config: nil)
      caller = config&.llm_caller || @_current_llm_caller
      raise ConfigurationError,
            "No llm_caller configured. Set it via LlmOptimizer.configure { |c| c.llm_caller = ->(prompt, model:) { ... } }" unless caller

      caller.call(prompt, model: model)
    end

    def elapsed_ms(start)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
    end

    def emit_log(logger, config, cache_status:, model_tier:, original_tokens:,
                 compressed_tokens:, latency_ms:, prompt:, response:)

      logger.info(
        "[llm_optimizer] { cache_status: #{cache_status.inspect}, " \
        "model_tier: #{model_tier.inspect}, " \
        "original_tokens: #{original_tokens.inspect}, " \
        "compressed_tokens: #{compressed_tokens.inspect}, " \
        "latency_ms: #{latency_ms.inspect} }"
      )

      if config.debug_logging
        logger.debug("[llm_optimizer] prompt=#{prompt.inspect} response=#{response.inspect}")
      end
    end

    def build_redis(redis_url)
      require "redis"
      Redis.new(url: redis_url)
    end
  end
end
