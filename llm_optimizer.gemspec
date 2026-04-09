# frozen_string_literal: true

require_relative "lib/llm_optimizer/version"

Gem::Specification.new do |spec|
  spec.name = "llm_optimizer"
  spec.version = LlmOptimizer::VERSION
  spec.authors = ["arun kumar"]
  spec.email = ["arunr.rubydev@gmail.com"]

  spec.summary = "Smart Gateway for LLM calls — semantic caching, model routing, token pruning, and history management."
  spec.description = "llm_optimizer reduces LLM API costs by up to 80% through semantic caching (Redis + vector similarity), intelligent model routing, token pruning, and conversation history summarization. Strictly opt-in and non-invasive."
  spec.homepage = "https://github.com/arunkumarry/llm_optimizer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/arunkumarry/llm_optimizer/tree/main"
  spec.metadata["changelog_uri"] = "https://github.com/arunkumarry/llm_optimizer/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "redis", "~> 5.0"
  spec.add_dependency "msgpack", "~> 1.7"
  spec.add_dependency "logger", "~> 1.6"

  # Development dependencies
  spec.add_development_dependency "prop_check", "~> 1.0"
  spec.add_development_dependency "mocha", "~> 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
