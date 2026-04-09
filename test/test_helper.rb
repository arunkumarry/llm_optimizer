# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Suppress warnings from third-party gems (e.g. prop_check)
module SuppressGemWarnings
  GEM_PATHS = Gem.path.map { |p| Regexp.escape(p) }.join("|")
  GEM_RE    = Regexp.new(GEM_PATHS).freeze

  def warn(msg, *args, **kwargs)
    return if msg.to_s.match?(GEM_RE)

    super
  end
end
Warning.extend(SuppressGemWarnings)

require "llm_optimizer"
require "minitest/autorun"
