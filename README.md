# llm_optimizer

A Smart Gateway for LLM API calls in Ruby and Rails applications. Reduces token usage and API costs through four composable optimizations — all opt-in, all independently configurable.

## How it works

Every call to `LlmOptimizer.optimize` passes through an ordered pipeline:

```
prompt → Compressor → ModelRouter → SemanticCache lookup → HistoryManager → LLM call → SemanticCache store → OptimizeResult
```

Each stage is independently enabled via configuration flags. If any stage fails at runtime, the gem falls through to a raw LLM call — your app never breaks because of the optimizer. (Misconfiguration, on the other hand, fails fast with an actionable error.)

## Quick Start

```ruby
LlmOptimizer.configure do |config|
  config.adapter = :ruby_llm            # how the gem talks to your LLM provider

  config.routing.simple_model  = "gpt-4o-mini"
  config.routing.complex_model = "claude-sonnet-4-5"

  config.cache.enabled = true           # semantic caching
  config.redis_url     = ENV["REDIS_URL"]
end

result = LlmOptimizer.optimize("What is Redis?")

result.response          # => "Redis is an in-memory data store..."
result.cache_status      # => :hit or :miss
result.model_tier        # => :simple or :complex
result.model             # => "gpt-4o-mini"
result.original_tokens   # => 5
result.latency_ms        # => 12.4
```

That's the whole setup: pick an adapter, name two models, flip the flags you want.

## Adapters

An adapter is the single integration point between the gem and your LLM provider. Built-ins:

| Adapter | Gem | Chat | Embeddings |
|---|---|---|---|
| `:ruby_llm` | [ruby_llm](https://rubygems.org/gems/ruby_llm) | OpenAI, Anthropic, Gemini, Bedrock, Ollama, … | ✅ |
| `:open_ai` | [ruby-openai](https://rubygems.org/gems/ruby-openai) | OpenAI | ✅ |
| `:anthropic` | [anthropic](https://rubygems.org/gems/anthropic) | Anthropic | ❌ (pair with `embedding_caller`) |

The adapter gems are not dependencies of llm_optimizer — add the one you use to your own Gemfile. Symbols use environment-variable API keys; instantiate the class for options:

```ruby
config.adapter = LlmOptimizer::Adapters::OpenAI.new(
  access_token: Rails.application.credentials.openai_api_key,
  embedding_model: "text-embedding-3-large"
)
```

Any other provider — or your existing service objects — via `Custom`:

```ruby
config.adapter = LlmOptimizer::Adapters::Custom.new(
  chat:  ->(messages, model:, tools: nil) {
    # messages is an Array of { role:, content: } hashes.
    # Return a String, or { content:, input_tokens:, output_tokens: }.
    MyLlmService.chat(messages, model: model)
  },
  embed: ->(text) { MyEmbeddingService.embed(text) }  # optional; needed for the cache
)
```

Lambdas are invoked defensively: the gem only passes the keyword arguments your lambda's signature accepts, so a plain `->(messages, model:)` keeps working as new keywords are added.

## Optimizations

### 1. Semantic Caching

Stores prompt embeddings in Redis. On subsequent calls, computes cosine similarity against stored embeddings. If similarity ≥ threshold, returns the cached response instantly — no LLM call made.

```ruby
config.cache.enabled   = true
config.cache.threshold = 0.96     # cosine similarity cutoff
config.cache.ttl       = 86_400   # seconds
config.cache.scope     = nil      # optional namespace (per user, tenant, ...)
config.redis_url       = ENV["REDIS_URL"]
```

### 2. Intelligent Model Routing

Classifies each prompt and routes it to the appropriate model tier:

- **Simple** → cheaper/faster model
- **Complex** → premium model

Routing uses a three-layer decision chain:

1. **Explicit override** — `config.routing.mode = :simple` / `:complex` (or per call: `route_to: :simple`)
2. **Fast-path signals** — code blocks and keywords (`analyze`, `refactor`, `debug`, `architect`, `explain in detail`) → instantly `:complex`, no LLM call
3. **LLM classifier** (optional) — for ambiguous prompts, asks a cheap model; falls back to a word-count heuristic if not configured or if the call fails

```ruby
config.routing.classifier_model = "gpt-4o-mini"  # enable the LLM classifier
```

This hybrid approach fixes the core weakness of pure heuristics:

- `"Fix this bug"` → 3 words but `:complex` via classifier
- `"Explain Ruby blocks simply"` → long but `:simple` via classifier
- `"analyze this code"` → keyword fast-path → `:complex` instantly (no classifier call)

If no classifier model is set, the router falls back to the word-count heuristic (< 20 words → `:simple`).

### 3. Token Pruning

Removes common English stop words from prompts before sending to the LLM. Preserves fenced code block content unchanged.

```ruby
config.compression.enabled = true
```

### 4. Conversation History Sliding Window

When a conversation history exceeds the configured token budget, summarizes the oldest messages using the simple model and replaces them with a single system summary message.

```ruby
config.history.enabled      = true
config.history.token_budget = 4000
```

## Installation

Add to your Gemfile (plus the adapter gem you use):

```ruby
gem "llm_optimizer"
gem "ruby_llm"   # or ruby-openai / anthropic
```

For Rails apps, generate the initializer:

```bash
rails generate llm_optimizer:install
```

This creates `config/initializers/llm_optimizer.rb` — a minimal working config with all advanced options documented in a commented appendix.

## Configuration reference

| Key | Type | Default | Description |
|---|---|---|---|
| `adapter` | Symbol/Object | `nil` | `:ruby_llm`, `:open_ai`, `:anthropic`, or an adapter instance |
| `redis_url` | String | `nil` | Redis URL (required for cache and conversations) |
| `routing.mode` | Symbol | `:auto` | `:auto`, `:simple`, or `:complex` |
| `routing.simple_model` | String | `"gpt-4o-mini"` | Model for simple prompts |
| `routing.complex_model` | String | `"claude-sonnet-4-5"` | Model for complex prompts |
| `routing.classifier_model` | String | `nil` | When set, ambiguous prompts are LLM-classified |
| `cache.enabled` | Boolean | `false` | Redis-backed semantic cache |
| `cache.threshold` | Float | `0.96` | Minimum cosine similarity for a hit |
| `cache.ttl` | Integer | `86_400` | Cache entry TTL in seconds |
| `cache.scope` | String | `nil` | Namespace cache entries (per user, tenant, …) |
| `cache.embedding_model` | String | `nil` | Embedding model override (adapter default otherwise) |
| `compression.enabled` | Boolean | `false` | Strip stop words before sending to the LLM |
| `history.enabled` | Boolean | `false` | Summarize old messages over the token budget |
| `history.token_budget` | Integer | `4000` | Token limit before summarization |
| `conversation.system_prompt` | String | `nil` | Seeded when a new `conversation_id` is created |
| `conversation.ttl` | Integer | `86_400` | Conversation TTL in seconds (`0` = no expiry) |
| `tools` | Array | `nil` | Tool definitions, passed through to the adapter |
| `schema` | Hash | `nil` | JSON schema for structured output (adapter support varies) |
| `logger` | Logger | `Logger.new($stdout)` | Any Logger-compatible object |
| `debug_logging` | Boolean | `false` | Log full prompt and response at DEBUG level |
| `timeout_seconds` | Integer | `5` | Timeout for external API calls |

Flat 0.1.x keys (`use_semantic_cache`, `compress_prompt`, `manage_history`, `route_to`, `similarity_threshold`, `token_budget`, `cache_ttl`, `cache_scope`, `simple_model`, `complex_model`, `system_prompt`, `conversation_ttl`, `with_tools`) still work as aliases of the grouped keys, as do the 0.1.x caller lambdas (`llm_caller`, `messages_caller`, `embedding_caller`, `classifier_caller`) — they are wrapped in a legacy adapter automatically. Both are deprecated in favor of the grouped keys and `config.adapter`.

### Fail-fast validation

`LlmOptimizer.configure` validates values immediately (bad routing mode, out-of-range threshold). Add one line at the end of your initializer to also catch cross-field problems (no adapter, cache without Redis, cache without embedding support) at boot instead of at the first LLM call:

```ruby
LlmOptimizer.validate!
```

## Per-call configuration

Override global config for a single call using options or a block:

```ruby
LlmOptimizer.optimize(prompt, route_to: :simple)

LlmOptimizer.optimize(prompt) do |config|
  config.routing.mode        = :simple
  config.compression.enabled = false
end
```

## Conversations

Pass a stable `conversation_id` and the gem loads history from Redis, calls the LLM with full context, and saves the updated history back:

```ruby
LlmOptimizer.optimize("What did I just ask?", conversation_id: "user-42")
LlmOptimizer.clear_conversation("user-42")
```

Or manage messages yourself and pass `messages:` — the result's `messages` field returns the final array (after any summarization) for the next turn.

## OptimizeResult

Every call returns an `OptimizeResult`:

| Field | Type | Description |
|---|---|---|
| `response` | String | The LLM response text |
| `model` | String | Model name actually used |
| `model_tier` | Symbol | `:simple` or `:complex` |
| `cache_status` | Symbol | `:hit` or `:miss` |
| `original_tokens` | Integer | Estimated token count before compression |
| `compressed_tokens` | Integer | Estimated tokens after compression (`nil` if not compressed) |
| `input_tokens` / `output_tokens` | Integer | Real usage when the adapter reports it |
| `latency_ms` | Float | Total wall-clock time for the optimize call |
| `messages` | Array | Final messages array sent to the LLM (`nil` on a cache hit) |

## Resilience

| Failure | Behavior |
|---|---|
| Redis unavailable (read) | Treat as cache miss, continue |
| Redis unavailable (write) | Log warning, return LLM result normally |
| Embedding API failure | Treat as cache miss, continue |
| Any component exception | Log error, fall through to raw LLM call |
| History summarization failure | Log warning, return original messages unchanged |
| Conversation load failure | Log warning, proceed without history |
| Conversation save failure | Log warning, return result with pre-save messages |

## Upgrading from 0.1.x

Existing initializers keep working — flat config keys and the caller lambdas are still accepted. To move to the new API:

1. Replace `llm_caller` / `messages_caller` / `embedding_caller` with one `config.adapter` (built-in symbol or `Adapters::Custom`).
2. Replace `classifier_caller` with `config.routing.classifier_model`.
3. Optionally switch flat keys to their grouped equivalents (`use_semantic_cache` → `cache.enabled`, etc.).
4. Add `LlmOptimizer.validate!` at the end of the initializer.

Note: enabling the cache without Redis/embedding support now raises a `ConfigurationError` instead of silently disabling the cache.

## Development

```bash
bundle install
bundle exec rake test     # run tests
bundle exec rake rubocop  # lint
bundle exec rake          # test + lint
```

## Contribution

See [CONTRIBUTING.md](https://github.com/arunkumarry/llm_optimizer/blob/main/CONTRIBUTING.md)

## License

MIT

---

[GitHub](https://github.com/arunkumarry/llm_optimizer) · [RubyGems](https://rubygems.org/gems/llm_optimizer) · [Changelog](https://github.com/arunkumarry/llm_optimizer/blob/main/CHANGELOG.md)
