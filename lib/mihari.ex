defmodule Mihari do
  @moduledoc """
  Public API for the Mihari log collection library.

  Mihari collects structured log entries and ships them to an HTTP endpoint
  with automatic batching, gzip compression, and retry logic.

  ## Quick Start

      # Send logs at various levels
      Mihari.info("User signed in", %{user_id: 42})
      Mihari.warn("Disk usage high", %{percent: 92})
      Mihari.error("Payment failed", %{order_id: "abc-123", reason: "timeout"})
      Mihari.debug("Cache miss", %{key: "user:42:profile"})

  ## Configuration

      # config/config.exs
      config :mihari_logger,
        endpoint: "https://logs.example.com/api/v1/logs",
        token: System.get_env("MIHARI_TOKEN"),
        batch_size: 10,
        flush_interval_ms: 5_000

  All log methods accept an optional metadata map that is merged with
  automatically captured system metadata (hostname, node, Elixir/OTP version).
  """

  @doc """
  Sends an info-level log entry.

  ## Examples

      Mihari.info("Request completed", %{duration_ms: 42, path: "/api/users"})

  """
  @spec info(String.t(), map()) :: :ok
  def info(message, metadata \\ %{}) do
    log(:info, message, metadata)
  end

  @doc """
  Sends a warn-level log entry.

  ## Examples

      Mihari.warn("Slow query detected", %{query_ms: 1200, table: "orders"})

  """
  @spec warn(String.t(), map()) :: :ok
  def warn(message, metadata \\ %{}) do
    log(:warn, message, metadata)
  end

  @doc """
  Sends an error-level log entry.

  ## Examples

      Mihari.error("Database connection lost", %{host: "db-primary", retries: 3})

  """
  @spec error(String.t(), map()) :: :ok
  def error(message, metadata \\ %{}) do
    log(:error, message, metadata)
  end

  @doc """
  Sends a debug-level log entry.

  ## Examples

      Mihari.debug("Cache lookup", %{key: "session:abc", hit: false})

  """
  @spec debug(String.t(), map()) :: :ok
  def debug(message, metadata \\ %{}) do
    log(:debug, message, metadata)
  end

  @doc """
  Sends a fatal-level log entry.

  ## Examples

      Mihari.fatal("System out of memory", %{available_mb: 12})

  """
  @spec fatal(String.t(), map()) :: :ok
  def fatal(message, metadata \\ %{}) do
    log(:fatal, message, metadata)
  end

  @doc """
  Forces an immediate flush of all queued log entries.

  Returns `{:ok, count}` on success or `{:error, reason}` on failure.
  """
  @spec flush() :: {:ok, non_neg_integer()} | {:error, term()}
  def flush do
    Mihari.Client.flush()
  end

  @doc """
  Returns the number of log entries currently queued and waiting to be sent.
  """
  @spec queue_size() :: non_neg_integer()
  def queue_size do
    Mihari.Client.queue_size()
  end

  # -- Private --

  defp log(level, message, metadata) do
    entry = Mihari.LogEntry.new(level, message, metadata)
    Mihari.Client.log(entry)
  end
end
