defmodule Mihari.TransportTest do
  use ExUnit.Case, async: true

  alias Mihari.Transport
  alias Mihari.LogEntry
  alias Mihari.Config

  setup do
    bypass = Bypass.open()
    endpoint = "http://localhost:#{bypass.port}/api/v1/logs"

    config = %Config{
      endpoint: endpoint,
      token: "test-bearer-token",
      batch_size: 10,
      flush_interval_ms: 5_000,
      max_retries: 1,
      retry_base_delay_ms: 10,
      gzip: false
    }

    %{bypass: bypass, config: config}
  end

  test "send_batch/2 with empty list returns {:ok, 0}", %{config: config} do
    assert {:ok, 0} = Transport.send_batch([], config)
  end

  test "send_batch/2 sends JSON payload and receives 202", %{bypass: bypass, config: config} do
    Bypass.expect_once(bypass, "POST", "/api/v1/logs", fn conn ->
      assert {"authorization", "Bearer test-bearer-token"} in conn.req_headers
      assert {"content-type", "application/json"} in conn.req_headers

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      assert is_list(decoded)
      assert length(decoded) == 2

      [first | _] = decoded
      assert Map.has_key?(first, "dt")
      assert Map.has_key?(first, "level")
      assert Map.has_key?(first, "message")

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(202, Jason.encode!(%{status: "accepted", count: 2}))
    end)

    entries = [
      LogEntry.new(:info, "first message", %{key: "a"}),
      LogEntry.new(:error, "second message", %{key: "b"})
    ]

    assert {:ok, 2} = Transport.send_batch(entries, config)
  end

  test "send_batch/2 with gzip sends compressed payload", %{bypass: bypass, config: config} do
    gzip_config = %{config | gzip: true}

    Bypass.expect_once(bypass, "POST", "/api/v1/logs", fn conn ->
      assert {"content-encoding", "gzip"} in conn.req_headers

      {:ok, compressed_body, conn} = Plug.Conn.read_body(conn)
      body = :zlib.gunzip(compressed_body)
      decoded = Jason.decode!(body)
      assert length(decoded) == 1
      assert hd(decoded)["message"] == "gzipped"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(202, Jason.encode!(%{status: "accepted", count: 1}))
    end)

    entries = [LogEntry.new(:info, "gzipped")]
    assert {:ok, 1} = Transport.send_batch(entries, gzip_config)
  end

  test "send_batch/2 retries on server error", %{bypass: bypass, config: config} do
    call_count = :counters.new(1, [:atomics])

    Bypass.expect(bypass, "POST", "/api/v1/logs", fn conn ->
      :counters.add(call_count, 1, 1)
      count = :counters.get(call_count, 1)

      if count == 1 do
        conn
        |> Plug.Conn.resp(500, "Internal Server Error")
      else
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(202, Jason.encode!(%{status: "accepted", count: 1}))
      end
    end)

    entries = [LogEntry.new(:info, "retry test")]
    assert {:ok, 1} = Transport.send_batch(entries, config)
    assert :counters.get(call_count, 1) == 2
  end

  test "send_batch/2 fails after exhausting retries", %{bypass: bypass, config: config} do
    Bypass.expect(bypass, "POST", "/api/v1/logs", fn conn ->
      conn |> Plug.Conn.resp(500, "Server Error")
    end)

    entries = [LogEntry.new(:info, "will fail")]
    assert {:error, {:http_error, 500, _}} = Transport.send_batch(entries, config)
  end

  test "send_batch/2 without token omits authorization header", %{bypass: bypass, config: config} do
    no_token_config = %{config | token: nil}

    Bypass.expect_once(bypass, "POST", "/api/v1/logs", fn conn ->
      refute Enum.any?(conn.req_headers, fn {k, _} -> k == "authorization" end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(202, Jason.encode!(%{status: "accepted", count: 1}))
    end)

    entries = [LogEntry.new(:info, "no auth")]
    assert {:ok, 1} = Transport.send_batch(entries, no_token_config)
  end

  test "backoff_delay/2 increases exponentially" do
    d0 = Transport.backoff_delay(0, 100)
    d1 = Transport.backoff_delay(1, 100)
    d2 = Transport.backoff_delay(2, 100)

    # Attempt 0: base=100, jitter 0..100 -> 100..200
    assert d0 >= 100 and d0 <= 200
    # Attempt 1: base=200, jitter 0..100 -> 200..300
    assert d1 >= 200 and d1 <= 300
    # Attempt 2: base=400, jitter 0..100 -> 400..500
    assert d2 >= 400 and d2 <= 500
  end
end
