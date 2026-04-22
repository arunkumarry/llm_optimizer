# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.5] - 2026-04-22

### Added
- `ConversationStore` — Redis-backed conversation persistence under the `llm_optimizer:conversation:<id>` namespace; handles load, save, TTL, and debug logging
- `conversation_id` option on `LlmOptimizer.optimize` — pass a stable ID and the gem automatically loads history from Redis, calls the LLM with full context, and saves the updated history back; no manual message management required
- `messages_caller` config option — injectable lambda `(messages, model:) -> String` for LLM providers that accept a full message array (OpenAI chat, Anthropic messages, etc.); takes priority over `llm_caller` when conversation history is present
- `system_prompt` config option — seeded as the opening exchange when a new conversation is created via `conversation_id`
- `conversation_ttl` config option — TTL in seconds for Redis conversation keys (default `86400`; `0` for no expiry)
- `LlmOptimizer.clear_conversation(conversation_id)` — deletes a conversation key from Redis; returns `true` if deleted, `false` if not found
- `pipeline#load_conversation` and `pipeline#persist_conversation` — internal helpers wiring `ConversationStore` into the optimize pipeline
- `pipeline#apply_history_manager` — applies `HistoryManager` sliding-window summarization to loaded conversation history when `manage_history: true`

### Changed
- `HistoryManager` now receives an internal `llm_caller` lambda that routes through `raw_llm_call`, so it correctly uses `messages_caller` when available instead of always requiring `llm_caller`
- `raw_llm_call` updated to prefer `messages_caller` over `llm_caller` when a non-empty messages array is present
- `ModelRouter` classifier response matching now uses word-boundary regex (`/\bsimple\b/`, `/\bcomplex\b/`) to handle decorated responses like `"simple."`, `"**complex**"`, or `"the answer is simple"` — previously only exact string match was used
- `ModelRouter` classifier failures (any `StandardError`) and unrecognized responses both fall through silently to the word-count heuristic; no exception is raised to the caller
- `validate_conversation_options!` raises `ConfigurationError` if both `conversation_id` and `messages:` are supplied, or if `conversation_id` is used without `redis_url`

### Fixed
- `HistoryManager` summarization raised `ConfigurationError: No llm_caller configured` when called inside the pipeline without a bound config — internal lambda now correctly captures `call_config`

## [0.1.4] - 2026-04-13

### Fixed
- `WrapperModule#chat` (used by `wrap_client`) incorrectly called `LlmOptimizer.optimize` internally which required `llm_caller` to be configured — causing `ConfigurationError` for users who only called `wrap_client`. Refactored into `optimize_pre_call` / `optimize_post_call` so the wrapped client handles the actual LLM call via `super`. `llm_caller` is no longer needed when using `wrap_client`

### Added
- `LlmOptimizer.optimize_pre_call(prompt, config)` — runs compress → route → cache lookup without making an LLM call; used internally by `WrapperModule` and available for advanced integrations
- `LlmOptimizer.optimize_post_call(pre_call_result, response, config)` — stores a response in the semantic cache after an LLM call; used internally by `WrapperModule`

## [0.1.3] - 2026-04-10

### Added
- `classifier_caller` config option — injectable lambda for LLM-based prompt classification
- Hybrid routing in `ModelRouter`: fast-path signals (code blocks, keywords) → LLM classifier → word-count heuristic fallback
- Fixes misclassification of short-but-complex prompts (e.g. "Fix this bug") and long-but-simple prompts
- Classifier failures (network errors, missing model, unexpected response) automatically fall through to heuristic — no app impact
- Tests for classifier integration, failure fallback, and fast-path bypass

### Changed
- `ModelRouter` routing logic now uses three-layer decision chain instead of pure heuristics
- README updated with classifier documentation and routing decision flow

## [0.1.2] - 2026-04-10

### Fixed
- `SemanticCache` used `pack("f*")` (32-bit) for both the Redis key hash and embedding serialization, causing precision loss on round-trip through MessagePack. Switched to `pack("G*")` / `unpack("G*")` (64-bit IEEE 754) — self-similarity is now exactly `1.0` and cache lookups work correctly with real embedding providers (Voyage AI, OpenAI, Cohere, etc.)
- `HistoryManager` summarization failed with `ConfigurationError: No llm_caller configured` when invoked through the gateway pipeline. The internal `raw_llm_call` lambda was missing `config: call_config`, so it couldn't resolve the user's configured `llm_caller`
- Updated `test/unit/test_gateway.rb` mock Redis helper to use `pack("G*")` to match the corrected `SemanticCache` key format

### Added
- `bin/test_semantic_cache.rb` — runnable smoke test for semantic cache using Voyage AI embeddings + Anthropic Claude
- `bin/test_history_manager.rb` — runnable smoke test for history manager sliding window using Anthropic Claude

## [0.1.1] - 2026-04-10

### Fixed
- RuboCop offenses across all source and test files
- `missing keyword: :_model` error in test lambdas — use `**_kwargs` pattern
- HistoryManager summarization tests failing due to keyword argument mismatch
- Suppress third-party gem warnings in test output

### Added
- Full unit test suite with positive and negative scenarios (Minitest + Mocha)
- Mock JSON fixtures for OpenAI embedding API responses
- `CONTRIBUTING.md` with fork setup, issue guidelines, PR checklist, and overcommit instructions
- Pre-commit hooks via overcommit (RuboCop + Minitest)
- Rails generator: `rails generate llm_optimizer:install`
- `embedding_caller` and `llm_caller` injectable lambdas — no forced provider dependency
- `logger` gem explicit dependency for Ruby 3.5+ compatibility

## [0.1.0] - 2026-04-10

### Added

- `LlmOptimizer.optimize(prompt, options = {}, &block)` — primary entry point returning an `OptimizeResult`
- `LlmOptimizer.configure` — global configuration with merge semantics (multiple calls merge without resetting)
- `LlmOptimizer.reset_configuration!` — resets global config to defaults (useful in tests)
- `LlmOptimizer.wrap_client(client_class)` — opt-in idempotent client wrapping via module prepend
- **Semantic Caching** — Redis-backed vector similarity cache using cosine similarity; configurable threshold and TTL
- **Intelligent Model Routing** — heuristic classifier routing prompts to `:simple` or `:complex` model tier based on word count, code blocks, and keywords
- **Token Pruning / Compressor** — English stop-word removal with fenced code block preservation; `estimate_tokens` helper
- **Conversation History Sliding Window** — summarizes oldest messages when token budget is exceeded; falls back to original messages on LLM failure
- **EmbeddingClient** — injectable `embedding_caller` lambda with OpenAI fallback via `OPENAI_API_KEY`
- **`llm_caller`** — injectable lambda to wire any LLM provider (RubyLLM, ruby-openai, Anthropic, Bedrock, etc.)
- **Rails generator** — `rails generate llm_optimizer:install` creates a pre-filled initializer
- **Railtie** — auto-loads generator when used in a Rails app
- **Structured logging** — INFO log per optimize call (no prompt content); DEBUG log with full prompt/response when `debug_logging: true`
- **Resilience** — all component failures fall through to raw LLM call; `EmbeddingError` treated as cache miss
- Full exception hierarchy: `LlmOptimizer::Error`, `ConfigurationError`, `EmbeddingError`, `TimeoutError`
- `OptimizeResult` struct with `response`, `model`, `model_tier`, `cache_status`, `original_tokens`, `compressed_tokens`, `latency_ms`, `messages`
- Unit test suite covering all components with positive and negative scenarios using Minitest + Mocha

[Unreleased]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/arunkumarry/llm_optimizer/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/arunkumarry/llm_optimizer/releases/tag/v0.1.0
