# frozen_string_literal: true

require_relative "../test_helper"
require "mocha/minitest"
require "json"

class TestEmbeddingClient < Minitest::Test
  FIXTURE_DIR = File.expand_path("../../fixtures", __FILE__)

  def openai_success_body
    File.read(File.join(FIXTURE_DIR, "openai_embedding_response.json"))
  end

  def openai_error_body
    File.read(File.join(FIXTURE_DIR, "openai_embedding_error.json"))
  end

  def expected_embedding
    JSON.parse(openai_success_body).dig("data", 0, "embedding")
  end

  # With embedding_caller

  def test_uses_embedding_caller_when_provided
    expected = [0.1, 0.2, 0.3]
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5,
      embedding_caller: ->(_text) { expected }
    )
    assert_equal expected, client.embed("hello")
  end

  def test_embedding_caller_receives_text
    received = nil
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5,
      embedding_caller: ->(text) { received = text; [0.1] }
    )
    client.embed("test input")
    assert_equal "test input", received
  end

  def test_embedding_caller_error_wrapped_in_embedding_error
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5,
      embedding_caller: ->(_text) { raise "network failure" }
    )
    assert_raises(LlmOptimizer::EmbeddingError) { client.embed("hello") }
  end

  def test_embedding_error_is_reraised_as_is
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5,
      embedding_caller: ->(_text) { raise LlmOptimizer::EmbeddingError, "already wrapped" }
    )
    err = assert_raises(LlmOptimizer::EmbeddingError) { client.embed("hello") }
    assert_equal "already wrapped", err.message
  end

  # Without embedding_caller (OpenAI fallback)

  def test_raises_embedding_error_when_no_api_key
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5
    )
    with_env("OPENAI_API_KEY" => nil) do
      assert_raises(LlmOptimizer::EmbeddingError) { client.embed("hello") }
    end
  end

  def test_raises_embedding_error_on_http_error_response
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5
    )

    mock_response = mock("http_response")
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    mock_response.stubs(:code).returns("401")
    mock_response.stubs(:body).returns(openai_error_body)

    mock_http = mock("http")
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:open_timeout=)
    mock_http.stubs(:read_timeout=)
    mock_http.stubs(:request).returns(mock_response)

    Net::HTTP.stubs(:new).returns(mock_http)

    with_env("OPENAI_API_KEY" => "test-key") do
      assert_raises(LlmOptimizer::EmbeddingError) { client.embed("hello") }
    end
  ensure
    Net::HTTP.unstub(:new)
  end

  def test_returns_embedding_array_on_success
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 5
    )

    mock_response = mock("http_response")
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
    mock_response.stubs(:body).returns(openai_success_body)

    mock_http = mock("http")
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:open_timeout=)
    mock_http.stubs(:read_timeout=)
    mock_http.stubs(:request).returns(mock_response)

    Net::HTTP.stubs(:new).returns(mock_http)

    with_env("OPENAI_API_KEY" => "test-key") do
      result = client.embed("hello")
      assert_equal expected_embedding, result
    end
  ensure
    Net::HTTP.unstub(:new)
  end

  def test_raises_embedding_error_on_timeout
    client = LlmOptimizer::EmbeddingClient.new(
      model: "text-embedding-3-small",
      timeout_seconds: 1
    )

    mock_http = mock("http")
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:open_timeout=)
    mock_http.stubs(:read_timeout=)
    mock_http.stubs(:request).raises(Net::ReadTimeout)

    Net::HTTP.stubs(:new).returns(mock_http)

    with_env("OPENAI_API_KEY" => "test-key") do
      assert_raises(LlmOptimizer::EmbeddingError) { client.embed("hello") }
    end
  ensure
    Net::HTTP.unstub(:new)
  end

  private

  def with_env(vars)
    old = vars.keys.map { |k| [k, ENV[k.to_s]] }.to_h
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end
end
