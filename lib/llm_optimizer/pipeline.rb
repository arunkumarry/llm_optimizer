# frozen_string_literal: true

module LlmOptimizer
  # Internal pipeline helpers — not part of the public API.
  # Extended into LlmOptimizer as private class methods.
  module Pipeline
    private

    def build_call_config(options, &block)
      cfg = Configuration.new
      cfg.merge!(configuration)
      options.each do |k, v|
        next unless Configuration::KNOWN_KEYS.include?(k.to_sym)

        cfg.public_send(:"#{k}=", v)
      end
      block&.call(cfg)
      cfg
    end

    def validate_conversation_options!(conversation_id, options, call_config)
      if conversation_id && options[:messages]
        raise ConfigurationError,
              "conversation_id and messages: are mutually exclusive — pass one or the other"
      end

      return unless conversation_id && call_config.redis_url.nil?

      raise ConfigurationError,
            "redis_url must be configured to use conversation_id"
    end

    def compress(prompt, config)
      return [prompt, nil] unless config.compress_prompt

      compressed = Compressor.new.compress(prompt)
      [compressed, Compressor.new.estimate_tokens(compressed)]
    end

    def route(prompt, config)
      router     = ModelRouter.new(config)
      model_tier = router.route(prompt)
      model      = model_tier == :simple ? config.simple_model : config.complex_model
      [model_tier, model]
    end

    def load_conversation(conversation_id, options, config)
      return [options[:messages], nil] unless conversation_id

      redis = build_redis(config.redis_url)
      store = ConversationStore.new(redis,
                                    ttl: config.conversation_ttl,
                                    logger: config.logger,
                                    debug_logging: config.debug_logging,
                                    system_prompt: config.system_prompt)
      [store.load(conversation_id), store]
    end

    def apply_history_manager(messages, config)
      return messages unless config.manage_history && messages

      llm_caller  = ->(p, model:) { raw_llm_call(p, model: model, config: config) }
      history_mgr = HistoryManager.new(
        llm_caller: llm_caller,
        simple_model: config.simple_model,
        token_budget: config.token_budget
      )
      history_mgr.process(messages)
    end

    def persist_conversation(store, conversation_id, messages, prompt, response)
      return messages unless store && conversation_id

      store.save(conversation_id, messages, prompt, response) || messages
    end

    def build_result(response, model, model_tier, cache_status,
                     original_tokens, compressed_tokens, latency_ms, messages, token_info = {})
      OptimizeResult.new(
        response: response, model: model, model_tier: model_tier,
        cache_status: cache_status, original_tokens: original_tokens,
        compressed_tokens: compressed_tokens,
        input_tokens: token_info[:input_tokens] || compressed_tokens || original_tokens,
        output_tokens: token_info[:output_tokens],
        cached_tokens: token_info[:cached_tokens],
        latency_ms: latency_ms,
        messages: messages
      )
    end

    def fallback_result(original_prompt, original_tokens, options, start)
      latency_ms = elapsed_ms(start)
      response, _token_info = raw_llm_call(original_prompt, model: nil, config: configuration)
      build_result(response, nil, nil, :miss, original_tokens || 0, nil,
                   latency_ms, options[:messages])
    end

    def raw_llm_call(prompt, model:, messages: nil, config: nil)
      tools = config&.with_tools || config&.tools
      result = if messages && !messages.empty? && config&.messages_caller
                 config.messages_caller.call(messages + [{ role: "user", content: prompt }], model: model, tools: tools)
               else
                 llm = config&.llm_caller || @_current_llm_caller
                 raise ConfigurationError, "No llm_caller configured." unless llm

                 llm.call(prompt, model: model, tools: tools)
               end

      if result.is_a?(Hash)
        [result[:content], result]
      else
        [result, {}]
      end
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
      logger.debug("[llm_optimizer] prompt=#{prompt.inspect} response=#{response.inspect}") if config.debug_logging
    end

    def build_redis(redis_url)
      require "redis"
      Redis.new(url: redis_url)
    end

    def semantic_cache_lookup(prompt, model, model_tier, original_tokens,
                              compressed_tokens, original_prompt, start, config)
      return [nil, nil] unless config.use_semantic_cache

      embedding = config.embedding_caller.call(prompt)
      cache     = SemanticCache.new(build_redis(config.redis_url),
                                    threshold: config.similarity_threshold,
                                    ttl: config.cache_ttl,
                                    cache_scope: config.cache_scope)
      cached, token_info = cache.lookup(embedding)

      if cached
        latency_ms = elapsed_ms(start)
        emit_log(config.logger, config,
                 cache_status: :hit, model_tier: model_tier,
                 original_tokens: original_tokens, compressed_tokens: compressed_tokens,
                 latency_ms: latency_ms, prompt: original_prompt, response: cached)

        [embedding, build_result(cached, model, model_tier, :hit,
                                 original_tokens, compressed_tokens, latency_ms, nil, token_info)]
      else
        [embedding, nil]
      end
    rescue StandardError => e
      config.logger.warn("[llm_optimizer] semantic_cache_lookup failed: #{e.message}")
      [nil, nil]
    end

    def store_in_cache(embedding, response, config, token_info = {})
      return unless config.use_semantic_cache && embedding

      SemanticCache.new(build_redis(config.redis_url),
                        threshold: config.similarity_threshold,
                        ttl: config.cache_ttl,
                        cache_scope: config.cache_scope).store(embedding, response, token_info)
    end
  end
end
