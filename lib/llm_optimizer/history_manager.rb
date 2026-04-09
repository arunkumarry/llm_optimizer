# frozen_string_literal: true

module LlmOptimizer
  class HistoryManager
    SUMMARIZE_COUNT = 10

    def initialize(llm_caller:, simple_model:, token_budget:)
      @llm_caller   = llm_caller
      @simple_model = simple_model
      @token_budget = token_budget
    end

    def estimate_tokens(messages)
      total_chars = messages.sum { |m| (m[:content] || m["content"] || "").length }
      total_chars / 4
    end

    def process(messages)
      return messages if estimate_tokens(messages) <= @token_budget

      count = [SUMMARIZE_COUNT, messages.length].min
      to_summarize = messages.first(count)
      remainder    = messages.drop(count)

      summary = summarize(to_summarize)
      return messages if summary.nil?

      [{ role: "system", content: summary }] + remainder
    end

    private

    def summarize(messages)
      conversation = messages.map { |m| "#{m[:role] || m["role"]}: #{m[:content] || m["content"]}" }.join("\n")
      prompt = "Summarize the following conversation history concisely, " \
               "preserving key facts and decisions:\n\n#{conversation}"

      @llm_caller.call(prompt, model: @simple_model)
    rescue StandardError => e
      warn "[llm_optimizer] HistoryManager summarization failed: #{e.message}"
      nil
    end
  end
end
