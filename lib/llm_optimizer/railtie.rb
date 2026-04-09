# frozen_string_literal: true

require "rails/railtie"

module LlmOptimizer
  class Railtie < Rails::Railtie
    generators do
      require "generators/llm_optimizer/install_generator"
    end
  end
end
