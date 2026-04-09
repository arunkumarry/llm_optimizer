# frozen_string_literal: true

require "rails/generators"

module LlmOptimizer
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a LlmOptimizer initializer in your Rails app"

      def copy_initializer
        template "initializer.rb", "config/initializers/llm_optimizer.rb"
      end
    end
  end
end
