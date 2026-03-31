defmodule MihariTest do
  use ExUnit.Case, async: false

  alias Mihari.LogEntry

  describe "public API" do
    test "info/2 creates an info-level entry and enqueues it" do
      entry = LogEntry.new(:info, "test info", %{key: "val"})
      assert entry.level == "info"
      assert entry.message == "test info"
      assert entry.metadata.key == "val"
    end

    test "warn/2 creates a warn-level entry" do
      entry = LogEntry.new(:warn, "test warn")
      assert entry.level == "warn"
    end

    test "error/2 creates an error-level entry" do
      entry = LogEntry.new(:error, "test error")
      assert entry.level == "error"
    end

    test "debug/2 creates a debug-level entry" do
      entry = LogEntry.new(:debug, "test debug")
      assert entry.level == "debug"
    end

    test "fatal/2 creates a fatal-level entry" do
      entry = LogEntry.new(:fatal, "test fatal")
      assert entry.level == "fatal"
    end
  end

  describe "LogEntry" do
    test "new/3 includes system metadata" do
      entry = LogEntry.new(:info, "hello")
      assert is_binary(entry.dt)
      assert Map.has_key?(entry.metadata, :hostname)
      assert Map.has_key?(entry.metadata, :node)
      assert Map.has_key?(entry.metadata, :elixir_version)
      assert Map.has_key?(entry.metadata, :otp_version)
      assert Map.has_key?(entry.metadata, :pid)
    end

    test "new/3 merges custom metadata with system metadata" do
      entry = LogEntry.new(:info, "hello", %{custom_key: "custom_val"})
      assert entry.metadata.custom_key == "custom_val"
      assert Map.has_key?(entry.metadata, :hostname)
    end

    test "to_map/1 flattens metadata into top-level map" do
      entry = LogEntry.new(:error, "boom", %{request_id: "abc"})
      map = LogEntry.to_map(entry)

      assert map.dt == entry.dt
      assert map.level == "error"
      assert map.message == "boom"
      assert map["request_id"] == "abc"
      assert map["hostname"]
    end

    test "new/3 raises for invalid level" do
      assert_raise FunctionClauseError, fn ->
        LogEntry.new(:invalid, "bad level")
      end
    end

    test "dt is a valid ISO 8601 timestamp" do
      entry = LogEntry.new(:info, "timestamp test")
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(entry.dt)
    end
  end
end
