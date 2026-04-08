# frozen_string_literal: true

require "digest"
require "msgpack"

module LlmOptimizer
  class SemanticCache
    KEY_NAMESPACE = "llm_optimizer:cache:"

    def initialize(redis_client, threshold:, ttl:)
      @redis     = redis_client
      @threshold = threshold
      @ttl       = ttl
    end

    def store(embedding, response)
      key     = cache_key(embedding)
      payload = MessagePack.pack({ "embedding" => embedding, "response" => response })
      @redis.set(key, payload, ex: @ttl)
    rescue ::Redis::BaseError => e
      warn "[llm_optimizer] SemanticCache store failed: #{e.message}"
    end

    def lookup(embedding)
      keys = @redis.keys("#{KEY_NAMESPACE}*")
      return nil if keys.empty?

      best_score    = -Float::INFINITY
      best_response = nil

      keys.each do |key|
        raw = @redis.get(key)
        next unless raw

        entry = MessagePack.unpack(raw)
        stored_embedding = entry["embedding"]
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
      KEY_NAMESPACE + Digest::SHA256.hexdigest(embedding.pack("f*"))
    end
  end
end
