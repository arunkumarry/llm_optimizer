# frozen_string_literal: true

require "logger"

module LlmOptimizer
  class Configuration
    # Base class for nested option groups (config.routing, config.cache, ...).
    # Tracks explicitly set keys so merge! only copies what the user touched.
    class Group
      class << self
        def settings
          @settings ||= {}
        end

        def setting(name, default: nil)
          settings[name] = default
          define_method(name) { @values.key?(name) ? @values[name] : self.class.settings[name] }
          define_method(:"#{name}=") do |value|
            @explicitly_set << name
            @values[name] = value
          end
        end
      end

      attr_reader :explicitly_set

      def initialize
        @values         = {}
        @explicitly_set = Set.new
      end

      def merge!(other)
        other.explicitly_set.each { |key| public_send(:"#{key}=", other.public_send(key)) }
        self
      end
    end

    class Routing < Group
      MODES = %i[auto simple complex].freeze

      setting :mode, default: :auto
      setting :simple_model, default: "gpt-4o-mini"
      setting :complex_model, default: "claude-sonnet-4-5"
      setting :classifier_model # when set, ambiguous prompts are classified by this model
    end

    class Cache < Group
      setting :enabled, default: false
      setting :threshold, default: 0.96
      setting :ttl, default: 86_400
      setting :scope
      setting :embedding_model # nil lets the adapter pick its own default
    end

    class Compression < Group
      setting :enabled, default: false
    end

    class History < Group
      setting :enabled, default: false
      setting :token_budget, default: 4000
    end

    class Conversation < Group
      setting :ttl, default: 86_400
      setting :system_prompt
    end

    GROUPS = {
      routing: Routing,
      cache: Cache,
      compression: Compression,
      history: History,
      conversation: Conversation
    }.freeze

    # Flat keys kept for 0.1.x compatibility and terse per-call overrides,
    # e.g. LlmOptimizer.optimize(prompt, route_to: :simple).
    ALIASES = {
      route_to: %i[routing mode],
      simple_model: %i[routing simple_model],
      complex_model: %i[routing complex_model],
      classifier_model: %i[routing classifier_model],
      use_semantic_cache: %i[cache enabled],
      similarity_threshold: %i[cache threshold],
      cache_ttl: %i[cache ttl],
      cache_scope: %i[cache scope],
      embedding_model: %i[cache embedding_model],
      compress_prompt: %i[compression enabled],
      manage_history: %i[history enabled],
      token_budget: %i[history token_budget],
      conversation_ttl: %i[conversation ttl],
      system_prompt: %i[conversation system_prompt]
    }.freeze

    TOP_LEVEL_KEYS = %i[
      adapter redis_url logger debug_logging timeout_seconds tools schema
      llm_caller messages_caller embedding_caller classifier_caller
    ].freeze

    TOP_LEVEL_DEFAULTS = {
      debug_logging: false,
      timeout_seconds: 5
    }.freeze

    # Every key accepted as a per-call option on LlmOptimizer.optimize.
    KNOWN_KEYS = (TOP_LEVEL_KEYS + ALIASES.keys + %i[with_tools]).freeze

    attr_reader :explicitly_set

    def initialize
      @explicitly_set = Set.new
      @values         = TOP_LEVEL_DEFAULTS.merge(logger: Logger.new($stdout))
      @groups         = GROUPS.transform_values(&:new)
    end

    GROUPS.each_key do |name|
      define_method(name) { @groups[name] }
    end

    TOP_LEVEL_KEYS.each do |key|
      define_method(key) { @values[key] }
      define_method(:"#{key}=") do |value|
        @explicitly_set << key
        @values[key] = value
      end
    end

    ALIASES.each do |alias_name, (group, attr)|
      define_method(alias_name) { @groups[group].public_send(attr) }
      define_method(:"#{alias_name}=") { |value| @groups[group].public_send(:"#{attr}=", value) }
    end

    # `with_tools` is an alias of `tools`.
    def with_tools
      tools
    end

    def with_tools=(value)
      self.tools = value
    end

    # Copies only explicitly set keys from other_config without resetting
    # unmentioned keys.
    def merge!(other_config)
      other_config.explicitly_set.each { |key| public_send(:"#{key}=", other_config.public_send(key)) }
      GROUPS.each_key { |name| @groups[name].merge!(other_config.public_send(name)) }
      self
    end

    # The adapter actually used for LLM calls: an explicit adapter instance,
    # a registry symbol (:ruby_llm, :open_ai, :anthropic), or — when only the
    # deprecated 0.1.x caller lambdas are set — a Legacy adapter wrapping them.
    def resolved_adapter
      case adapter
      when nil then legacy_adapter
      when Symbol, String then Adapters.resolve(adapter, **symbol_adapter_options)
      else adapter
      end
    end

    def embedding_support?
      !embedding_caller.nil? || !!resolved_adapter&.supports_embedding?
    end

    # Cheap value-level checks, run on every `LlmOptimizer.configure`.
    def validate_values!
      errors = value_errors
      raise ConfigurationError, format_errors(errors) unless errors.empty?

      true
    end

    # Full cross-field validation. Run automatically on each optimize call;
    # call `LlmOptimizer.validate!` from your initializer to fail fast at boot.
    def validate!
      errors = value_errors + cross_field_errors
      raise ConfigurationError, format_errors(errors) unless errors.empty?

      true
    end

    def method_missing(name, *args, &)
      key = name.to_s.chomp("=").to_sym
      raise ConfigurationError, "Unknown configuration key: #{key}" unless KNOWN_KEYS.include?(key)

      super
    end

    def respond_to_missing?(name, include_private = false)
      key = name.to_s.chomp("=").to_sym
      KNOWN_KEYS.include?(key) || super
    end

    private

    def value_errors
      errors = []
      unless Routing::MODES.include?(routing.mode)
        errors << "routing.mode must be one of :auto, :simple, :complex (got #{routing.mode.inspect})"
      end
      unless cache.threshold.is_a?(Numeric) && cache.threshold.between?(0, 1)
        errors << "cache.threshold must be a number between 0 and 1 (got #{cache.threshold.inspect})"
      end
      errors
    end

    def cross_field_errors
      errors = []
      errors.concat(adapter_errors)
      errors.concat(cache_errors)
      errors
    rescue ConfigurationError => e
      errors << e.message
      errors
    end

    def adapter_errors
      return [] if resolved_adapter

      ["no adapter configured. Set config.adapter = :ruby_llm (or :open_ai, :anthropic), " \
       "or pass your own: config.adapter = LlmOptimizer::Adapters::Custom.new(chat: ->(messages, model:) { ... })"]
    end

    def cache_errors
      return [] unless cache.enabled

      errors = []
      unless redis_url
        errors << "cache.enabled is true but redis_url is not set. " \
                  "Set config.redis_url (e.g. ENV[\"REDIS_URL\"]) or disable the cache."
      end
      unless embedding_support?
        errors << "cache.enabled is true but the configured adapter does not support embeddings. " \
                  "Use an adapter with embeddings (:ruby_llm, :open_ai) or set config.embedding_caller."
      end
      errors
    end

    def format_errors(errors)
      "Invalid LlmOptimizer configuration:\n- #{errors.join("\n- ")}"
    end

    def symbol_adapter_options
      return {} unless cache.explicitly_set.include?(:embedding_model)

      { embedding_model: cache.embedding_model }
    end

    def legacy_adapter
      return nil unless llm_caller || messages_caller || embedding_caller

      Adapters::Legacy.new(llm_caller: llm_caller, messages_caller: messages_caller,
                           embedding_caller: embedding_caller)
    end
  end
end
