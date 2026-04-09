# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module LlmOptimizer
  class EmbeddingClient
    OPENAI_ENDPOINT = "https://api.openai.com/v1/embeddings"

    def initialize(model:, timeout_seconds:, embedding_caller: nil)
      @model            = model
      @timeout_seconds  = timeout_seconds
      @embedding_caller = embedding_caller
    end

    def embed(text)
      if @embedding_caller
        @embedding_caller.call(text)
      else
        embed_via_openai(text)
      end
    rescue EmbeddingError
      raise
    rescue StandardError => e
      raise EmbeddingError, "Embedding request failed: #{e.message}"
    end

    private

    def embed_via_openai(text)
      api_key = ENV.fetch("OPENAI_API_KEY", nil)
      if api_key.nil? || api_key.empty?
        raise EmbeddingError,
              "OPENAI_API_KEY is not set and no embedding_caller configured"
      end

      uri  = URI(OPENAI_ENDPOINT)
      body = JSON.generate({ model: @model, input: text })

      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      request                  = Net::HTTP::Post.new(uri.path)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body             = body

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise EmbeddingError, "OpenAI embeddings API returned #{response.code}: #{response.body}"
      end

      parsed = JSON.parse(response.body)
      parsed.dig("data", 0, "embedding") or
        raise EmbeddingError, "Unexpected response shape: #{response.body}"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise EmbeddingError, "Embedding request timed out: #{e.message}"
    end
  end
end
