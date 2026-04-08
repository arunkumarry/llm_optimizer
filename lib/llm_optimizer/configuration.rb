# frozen_string_literal: true

require "logger"
require "set"

module LlmOptimizer
  class Configuration
    KNOWN_KEYS = %i[
      use_semantic_cache
      compress_prompt
      manage_history
      route_to
      similarity_threshold
      token_budget
      redis_url
      embedding_model
      simple_model
      complex_model
      logger
      debug_logging
      timeout_seconds
      cache_ttl
      llm_caller
    ].freeze

    attr_accessor(*KNOWN_KEYS)

    def initialize
      @explicitly_set = Set.new

      @use_semantic_cache   = false
      @compress_prompt      = false
      @manage_history       = false
      @route_to             = :auto
      @similarity_threshold = 0.96
      @token_budget         = 4000
      @redis_url            = nil
      @embedding_model      = "text-embedding-3-small"
      @simple_model         = "gpt-4o-mini"
      @complex_model        = "claude-3-5-sonnet-20241022"
      @logger               = Logger.new($stdout)
      @debug_logging        = false
      @timeout_seconds      = 5
      @cache_ttl            = 86400
      @llm_caller           = nil
      @embedding_caller     = nil
    end

    # Copies only explicitly set keys from other_config without resetting unmentioned keys.
    def merge!(other_config)
      other_config.instance_variable_get(:@explicitly_set).each do |key|
        public_send(:"#{key}=", other_config.public_send(key))
      end
      self
    end

    def method_missing(name, *args, &block)
      key = name.to_s.chomp("=").to_sym
      raise ConfigurationError, "Unknown configuration key: #{key}" unless KNOWN_KEYS.include?(key)

      super
    end

    def respond_to_missing?(name, include_private = false)
      key = name.to_s.chomp("=").to_sym
      KNOWN_KEYS.include?(key) || super
    end

    # Override generated attr_accessor setters to track explicitly set keys.
    KNOWN_KEYS.each do |key|
      define_method(:"#{key}=") do |value|
        @explicitly_set << key
        instance_variable_set(:"@#{key}", value)
      end
    end
  end
end
