# frozen_string_literal: true

module LlmOptimizer
  class ConversationStore
    KEY_NAMESPACE = "llm_optimizer:conversation:"

    def initialize(redis_client, ttl:, logger:, debug_logging: false, system_prompt: nil)
      @redis         = redis_client
      @ttl           = ttl
      @logger        = logger
      @debug_logging = debug_logging
      @system_prompt = system_prompt
    end

    # Loads and returns the messages array for conversation_id.
    # Returns [] if no key exists or on Redis error (logs warning).
    def load(conversation_id)
      key = redis_key(conversation_id)
      raw = @redis.get(key)

      if raw.nil?
        messages = seed_messages
        @logger.info("[llm_optimizer] ConversationStore load: conversation_id=#{conversation_id}, count=#{messages.size}")
        log_debug_history(conversation_id, messages)
        return messages
      end

      messages = JSON.parse(raw, symbolize_names: true)
      @logger.info("[llm_optimizer] ConversationStore load: conversation_id=#{conversation_id}, count=#{messages.size}")
      log_debug_history(conversation_id, messages)
      messages
    rescue Redis::BaseError => e
      @logger.warn("[llm_optimizer] ConversationStore load failed: conversation_id=#{conversation_id}, error=#{e.message}")
      []
    end

    # Appends user + assistant messages to history and persists to Redis.
    # Silently logs warning on Redis error; never raises.
    def save(conversation_id, messages, prompt, response)
      updated_messages = messages + [
        { role: "user", content: prompt },
        { role: "assistant", content: response }
      ]

      key = redis_key(conversation_id)
      json = JSON.generate(updated_messages)

      if @ttl.zero?
        @redis.set(key, json)
      else
        @redis.set(key, json, ex: @ttl)
      end

      @logger.info("[llm_optimizer] ConversationStore save: conversation_id=#{conversation_id}, count=#{updated_messages.size}")
      log_debug_history(conversation_id, updated_messages)
      updated_messages
    rescue Redis::BaseError => e
      @logger.warn("[llm_optimizer] ConversationStore save failed: conversation_id=#{conversation_id}, error=#{e.message}")
      nil
    end

    private

    def redis_key(conversation_id)
      "#{KEY_NAMESPACE}#{conversation_id}"
    end

    def seed_messages
      return [] unless @system_prompt

      [
        { role: "user",      content: @system_prompt },
        { role: "assistant", content: "Got it!" }
      ]
    end

    def log_debug_history(conversation_id, messages)
      return unless @debug_logging

      @logger.debug("[llm_optimizer] ConversationStore history: conversation_id=#{conversation_id}, messages=#{messages.inspect}")
    end
  end
end
