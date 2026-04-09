# frozen_string_literal: true

module LlmOptimizer
  class Compressor
    STOP_WORDS = %w[
      the a an is are was were be been being
      of in to for on at by with from as into
      through during before after above below
      between out off over under again further
      then once
    ].freeze

    FENCE_RE = /(```[\s\S]*?```|~~~[\s\S]*?~~~)/

    def initialize(slm_client: nil)
      @slm_client = slm_client
    end

    def compress(prompt)
      segments = prompt.split(FENCE_RE)

      processed = segments.map.with_index do |segment, i|
        # Odd-indexed segments are fenced code blocks (captured group)
        if i.odd?
          segment
        else
          remove_stop_words(segment)
        end
      end

      result = processed.join
      result.gsub(/\s{2,}/, " ").strip
    end

    def estimate_tokens(text)
      (text.length / 4.0).ceil
    end

    private

    def remove_stop_words(text)
      stop_set = STOP_WORDS.to_set
      words = text.split
      words.reject { |w| stop_set.include?(w.downcase) }.join(" ")
    end
  end
end
