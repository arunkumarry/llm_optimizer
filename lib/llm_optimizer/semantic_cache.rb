# frozen_string_literal: true

require "digest"
require "msgpack"

module LlmOptimizer
  class SemanticCache
    KEY_NAMESPACE = "llm_optimizer:cache:"

    def initialize(redis_client, threshold:, ttl:, cache_scope: nil)
      @redis       = redis_client
      @threshold   = threshold
      @ttl         = ttl
      @cache_scope = cache_scope
    end

    def store(embedding, response)
      key     = cache_key(embedding)
      # Serialize embedding as raw 64-bit big-endian doubles to preserve full
      # Float precision. MessagePack silently downcasts Ruby Float to 32-bit,
      # which corrupts cosine similarity on deserialization.
      payload = MessagePack.pack({
                                   "embedding" => embedding.pack("G*"), # binary string, lossless
                                   "response" => response
                                 })
      @redis.set(key, payload, ex: @ttl)
    rescue ::Redis::BaseError => e
      warn "[llm_optimizer] SemanticCache store failed: #{e.message}"
    end

    def lookup(embedding)
      prefix = KEY_NAMESPACE
      prefix += "#{@cache_scope}:" if @cache_scope
      keys = @redis.keys("#{prefix}*")

      # If no scope is provided, exclude keys that belong to a scope (contain more than 2 colons)
      # to ensure isolation from scoped entries.
      keys.reject! { |k| k.count(":") > 2 } unless @cache_scope

      return nil if keys.empty?

      best_score    = -Float::INFINITY
      best_response = nil

      keys.each do |key|
        raw = @redis.get(key)
        next unless raw

        entry = MessagePack.unpack(raw)
        # Unpack the binary string back to 64-bit doubles
        stored_embedding = entry["embedding"].unpack("G*")
        score = cosine_similarity(embedding, stored_embedding)

        if score > best_score
          best_score    = score
          best_response = entry["response"]
        end
      end

      best_score >= @threshold ? best_response : nil
    rescue ::Redis::BaseError => e
      warn "[llm_optimizer] SemanticCache lookup failed: #{e.message}"
      nil
    end

    def cosine_similarity(vec_a, vec_b)
      dot    = vec_a.zip(vec_b).sum { |a, b| a * b }
      mag_a  = Math.sqrt(vec_a.sum { |x| x * x })
      mag_b  = Math.sqrt(vec_b.sum { |x| x * x })
      return 0.0 if mag_a.zero? || mag_b.zero?

      dot / (mag_a * mag_b)
    end

    private

    def cache_key(embedding)
      # Use "G*" (64-bit big-endian double) to match Ruby's native Float precision.
      # "f*" (32-bit) truncates precision and produces inconsistent hashes for the
      # same embedding across serialize/deserialize round trips.
      prefix = KEY_NAMESPACE
      prefix += "#{@cache_scope}:" if @cache_scope
      prefix + Digest::SHA256.hexdigest(embedding.pack("G*"))
    end
  end
end
