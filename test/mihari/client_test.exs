defmodule Mihari.ClientTest do
  use ExUnit.Case, async: false

  alias Mihari.Client
  alias Mihari.LogEntry

  setup do
    # Start a fresh client for each test with a unique name
    name = :"client_test_#{System.unique_integer([:positive])}"

    # Set test config
    Application.put_env(:mihari_logger, :endpoint, "http://localhost:9999/api/v1/logs")
    Application.put_env(:mihari_logger, :token, "test-token")
    Application.put_env(:mihari_logger, :batch_size, 3)
    Application.put_env(:mihari_logger, :flush_interval_ms, 60_000)
    Application.put_env(:mihari_logger, :max_retries, 0)
    Application.put_env(:mihari_logger, :gzip, false)

    {:ok, pid} = Client.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
    end)

    %{client: name, pid: pid}
  end

  test "starts and has empty queue", %{client: client} do
    assert Client.queue_size(client) == 0
  end

  test "log/2 enqueues entries", %{client: client} do
    entry = LogEntry.new(:info, "test message")
    :ok = Client.log(entry, client)

    # Give the cast time to process
    :timer.sleep(10)
    assert Client.queue_size(client) == 1
  end

  test "multiple logs accumulate in queue", %{client: client} do
    for i <- 1..2 do
      entry = LogEntry.new(:info, "message #{i}")
      Client.log(entry, client)
    end

    :timer.sleep(10)
    assert Client.queue_size(client) == 2
  end

  test "flush/1 with empty queue returns {:ok, 0}", %{client: client} do
    assert {:ok, 0} = Client.flush(client)
  end
end
