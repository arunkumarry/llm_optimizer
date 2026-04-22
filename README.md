# llm_optimizer

A Smart Gateway for LLM API calls in Ruby and Rails applications. Reduces token usage and API costs through four composable optimizations all opt-in, all independently configurable.

## How it works

Every call to `LlmOptimizer.optimize` passes through an ordered pipeline:

```
prompt → Compressor → ModelRouter → SemanticCache lookup → HistoryManager → LLM call → SemanticCache store → OptimizeResult
```

Each stage is independently enabled via configuration flags. If any stage fails, the gem falls through to a raw LLM call your app never breaks because of the optimizer.

## Optimizations

### 1. Semantic Caching
Stores prompt embeddings in Redis. On subsequent calls, computes cosine similarity against stored embeddings. If similarity ≥ threshold, returns the cached response instantly no LLM call made.

### 2. Intelligent Model Routing

Classifies each prompt and routes it to the appropriate model tier:

- **Simple** → cheaper/faster model (e.g. `llama3`, `gemini-2.5-flash-lite`)
- **Complex** → premium model (e.g. `claude-haiku-4-5-20251001`, `gemini-3.0-pro`)

Routing uses a three-layer decision chain:

1. **Explicit override** — if `route_to: :simple` or `:complex` is set, always use that
2. **Fast-path signals** — code blocks (` ``` `, `~~~`) and keywords (`analyze`, `refactor`, `debug`, `architect`, `explain in detail`) → instantly `:complex`, no LLM call
3. **LLM classifier** (optional) — for ambiguous prompts, calls a cheap model with a classification prompt; falls back to word-count heuristic if not configured or if the call fails

This hybrid approach fixes the core weakness of pure heuristics:
- `"Fix this bug"` → 3 words but `:complex` via classifier
- `"Explain Ruby blocks simply"` → long but `:simple` via classifier
- `"analyze this code"` → keyword fast-path → `:complex` instantly (no classifier call)

Configure the classifier with any cheap model your app already uses:

```ruby
config.classifier_caller = ->(prompt) {
  RubyLLM.chat(model: "amazon.nova-micro-v1:0", provider: :bedrock, assume_model_exists: true)
    .ask(prompt).content.strip.downcase
}
```

If `classifier_caller` is not set, the router falls back to the word-count heuristic (< 20 words → `:simple`).

### 3. Token Pruning
Removes common English stop words from prompts before sending to the LLM. Preserves fenced code block content unchanged. Typically reduces token count by 10–20%.

### 4. Conversation History Sliding Window
When a conversation history exceeds the configured token budget, summarizes the oldest messages using the simple model and replaces them with a single system summary message. Uses Redis to store for fast reetreival and summarizing.

## Installation

Add to your Gemfile:

```ruby
gem "llm_optimizer"
```

Then run:

```bash
bundle install
```

For Rails apps, generate the initializer:

```bash
rails generate llm_optimizer:install
```

This creates `config/initializers/llm_optimizer.rb` with all options pre-filled and commented.

## Quick Start

```ruby
LlmOptimizer.configure do |config|
  config.compress_prompt    = true
  config.use_semantic_cache = true
  config.redis_url          = ENV["REDIS_URL"]

  # Wire up your app's LLM client
  config.llm_caller = ->(prompt, model:) {
    # Use whatever LLM client your app already has
    MyLlmService.chat(prompt, model: model)
  }

  # Wire up your embeddings provider (required if use_semantic_cache: true)
  config.embedding_caller = ->(text) {
    MyEmbeddingService.embed(text)
  }
end

result = LlmOptimizer.optimize("What is Redis?")

puts result.response          # => "Redis is an in-memory data store..."
puts result.cache_status      # => :hit or :miss
puts result.model_tier        # => :simple or :complex
puts result.model             # => "gemini-2.5-flash-lite"
puts result.original_tokens   # => 5
puts result.compressed_tokens # => 4
puts result.latency_ms        # => 12.4
```

## Configuration

### Rails initializer

```ruby
# config/initializers/llm_optimizer.rb
require "llm_optimizer"

LlmOptimizer.configure do |config|
  # --- Feature flags (all off by default) ---
  config.compress_prompt    = true   # strip stop words before sending to LLM
  config.use_semantic_cache = true   # cache responses by vector similarity
  config.manage_history     = true   # summarize old messages when over token budget

  # --- Model routing ---
  config.route_to      = :auto                        # :auto, :simple, or :complex
  config.simple_model  = "gemini-2.5-flash-lite" # used for simple prompts
  config.complex_model = "claude-haiku-4-5-20251001" # used for complex prompts

  # --- Redis (required if use_semantic_cache: true) ---
  config.redis_url = ENV["REDIS_URL"]

  # --- Token / cache settings ---
  config.similarity_threshold = 0.96   # cosine similarity cutoff for cache hit
  config.token_budget         = 4000   # max tokens before history summarization
  config.cache_ttl            = 86400  # cache TTL in seconds (24h)
  config.timeout_seconds      = 5      # timeout for external API calls

  # --- Logging ---
  config.logger        = Rails.logger
  config.debug_logging = Rails.env.development? # logs full prompt+response in dev

  # --- Wire up your app's LLM client ---
  # Replace the body with however your app calls the LLM
  config.llm_caller = ->(prompt, model:) {
    model ||= "claude-haiku-4-5-20251001"
    provider = if model.include?("claude") then :anthropic
               elsif model.include?("gpt") then :openai
               elsif model.include?("gemini") then :gemini
               else :ollama
               end
    chat = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
    chat.ask(prompt).content
  }

  # Embeddings caller — wire to your embeddings provider (required if use_semantic_cache: true)
  config.embedding_caller = ->(text) {
    response = RubyLLM.embed(text, provider: :gemini, model: 'gemini-embedding-001')
    response.vectors
  }

  # Classifier caller — optional, improves routing accuracy for ambiguous prompts
  # Falls back to word-count heuristic if not set or if the call fails
  config.classifier_caller = ->(prompt) {
    RubyLLM.chat(model: "amazon.nova-micro-v1:0", provider: :bedrock, assume_model_exists: true)
      .ask(prompt).content.strip.downcase
  }

  # Messages caller - optional, handles converation summary and hostiry manager.
  config.system_prompt = "You are a sarcastic comic person who gives witty responses in a non harmful way. If any serious question is asked, handle it in a calm way."

  config.messages_caller = ->(messages, model:) {
    chat = RubyLLM.chat(model: model)
    messages[0..-2].each { |m| chat.add_message(role: m[:role], content: m[:content]) }
    response = chat.ask(messages.last[:content])
    response.content
  }
end

```

### Configuration reference

| Key | Type | Default | Description |
|---|---|---|---|
| `compress_prompt` | Boolean | `false` | Strip stop words before sending to LLM |
| `use_semantic_cache` | Boolean | `false` | Enable Redis-backed semantic cache |
| `manage_history` | Boolean | `false` | Enable conversation history summarization |
| `route_to` | Symbol | `:auto` | `:auto`, `:simple`, or `:complex` |
| `simple_model` | String | `"gemini-2.5-flash-lite"` | Model for simple prompts |
| `complex_model` | String | `"claude-haiku-4-5-20251001"` | Model for complex prompts |
| `similarity_threshold` | Float | `0.96` | Minimum cosine similarity for cache hit |
| `token_budget` | Integer | `4000` | Token limit before history summarization |
| `cache_ttl` | Integer | `86400` | Cache entry TTL in seconds |
| `timeout_seconds` | Integer | `5` | Timeout for external API calls |
| `redis_url` | String | `nil` | Redis connection URL |
| `embedding_model` | String | `"gemini-embedding-001"` | Embedding model name (OpenAI fallback) |
| `logger` | Logger | `Logger.new($stdout)` | Any Logger-compatible object |
| `debug_logging` | Boolean | `false` | Log full prompt and response at DEBUG level |
| `llm_caller` | Lambda | `nil` | `(prompt, model:) -> String` |
| `embedding_caller` | Lambda | `nil` | `(text) -> Array<Float>` |
| `classifier_caller` | Lambda | `nil` | `(prompt) -> "simple" or "complex"` |
| `messages_caller` | Lambda | `nil` | `(messages, model:) -> String` — used when `conversation_id` is present; receives full history including current user turn |
| `system_prompt` | String | `nil` | Seeded as the first system message when a new conversation is created via `conversation_id` |
| `conversation_ttl` | Integer | `86400` | TTL in seconds for Redis-backed conversation history (`0` for no expiry) |

## Per-call configuration

Override global config for a single call using a block:

```ruby
result = LlmOptimizer.optimize(prompt) do |config|
  config.route_to      = :simple
  config.compress_prompt = false
end
```

## Conversation history

Pass a `messages` array to enable history management:

```ruby
messages = [
  { role: "user",      content: "Tell me about Redis" },
  { role: "assistant", content: "Redis is an in-memory data store..." },
  # ... more messages
]

result = LlmOptimizer.optimize("What else can it do?", messages: messages)

## OptimizeResult

Every call returns an `OptimizeResult` struct:

| Field | Type | Description |
|---|---|---|
| `response` | String | The LLM response text |
| `model` | String | Model name actually used |
| `model_tier` | Symbol | `:simple` or `:complex` |
| `cache_status` | Symbol | `:hit` or `:miss` |
| `original_tokens` | Integer | Estimated token count before compression |
| `compressed_tokens` | Integer | Estimated token count after compression (`nil` if not compressed) |
| `latency_ms` | Float | Total wall-clock time for the optimize call |
| `messages` | Array | Final messages array sent to the LLM, after history management and conversation hydration (`nil` on a cache hit) |

The `messages` field reflects the actual array passed to `messages_caller` (or built from `conversation_id`), including any summarization applied by the history manager. You can pass it back as `options[:messages]` on the next call to continue a stateless conversation.

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

## Development

```bash
bundle install
bundle exec rake test     # run tests
bundle exec rake rubocop  # lint
bundle exec rake          # test + lint
```

Generate the Rails initializer in a target app:

```bash
rails generate llm_optimizer:install
```

## Contribution
See [CONTRIBUTING.md](https://github.com/arunkumarry/llm_optimizer/blob/main/CONTRIBUTING.md)

## License

MIT

---

[GitHub](https://github.com/arunkumarry/llm_optimizer) · [RubyGems](https://rubygems.org/gems/llm_optimizer) · [Changelog](https://github.com/arunkumarry/llm_optimizer/blob/main/CHANGELOG.md)
