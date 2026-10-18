# frozen_string_literal: true

module LlmOptimizer
  # Invokes user-supplied callables (lambdas, procs, or any object responding
  # to #call), passing only the keyword arguments the callable's signature
  # accepts. This lets the gem add new keywords (tools:, schema:, ...) over
  # time without breaking lambdas written against an older signature.
  module Invoker
    module_function

    def call(callable, *, **kwargs)
      params = parameters_for(callable)
      return callable.call(*, **kwargs) if params.nil? || params.any? { |type, _name| type == :keyrest }

      accepted = params.filter_map { |type, name| name if %i[key keyreq].include?(type) }
      callable.call(*, **kwargs.slice(*accepted))
    end

    def parameters_for(callable)
      return callable.parameters if callable.respond_to?(:parameters)

      callable.method(:call).parameters
    rescue NameError
      nil
    end
  end
end
