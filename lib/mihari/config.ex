defmodule Mihari.Config do
  @moduledoc """
  Configuration module for Mihari.

  ## Configuration Options

    * `:endpoint` - The HTTP endpoint to send logs to (required)
    * `:token` - Bearer token for authentication (required)
    * `:batch_size` - Number of log entries to batch before sending (default: 10)
    * `:flush_interval_ms` - Milliseconds between automatic flushes (default: 5000)
    * `:max_retries` - Maximum number of retry attempts on failure (default: 3)
    * `:retry_base_delay_ms` - Base delay in ms for exponential backoff (default: 1000)
    * `:gzip` - Whether to gzip compress the payload (default: true)

  ## Example

      config :mihari,
        endpoint: "https://logs.example.com/api/v1/logs",
        token: "your-api-token",
        batch_size: 10,
        flush_interval_ms: 5_000

  """

  @type t :: %__MODULE__{
          endpoint: String.t(),
          token: String.t() | nil,
          batch_size: pos_integer(),
          flush_interval_ms: pos_integer(),
          max_retries: non_neg_integer(),
          retry_base_delay_ms: pos_integer(),
          gzip: boolean()
        }

  @enforce_keys [:endpoint]
  defstruct [
    :endpoint,
    :token,
    batch_size: 10,
    flush_interval_ms: 5_000,
    max_retries: 3,
    retry_base_delay_ms: 1_000,
    gzip: true
  ]

  @doc """
  Reads the current configuration from the application environment
  and returns a `%Mihari.Config{}` struct.

  Raises if `:endpoint` is not configured.
  """
  @spec read!() :: t()
  def read! do
    endpoint =
      Application.get_env(:mihari, :endpoint) ||
        raise ArgumentError, "Mihari :endpoint must be configured"

    %__MODULE__{
      endpoint: endpoint,
      token: Application.get_env(:mihari, :token),
      batch_size: Application.get_env(:mihari, :batch_size, 10),
      flush_interval_ms: Application.get_env(:mihari, :flush_interval_ms, 5_000),
      max_retries: Application.get_env(:mihari, :max_retries, 3),
      retry_base_delay_ms: Application.get_env(:mihari, :retry_base_delay_ms, 1_000),
      gzip: Application.get_env(:mihari, :gzip, true)
    }
  end

  @doc """
  Returns default system metadata captured automatically with every log entry.
  """
  @spec system_metadata() :: map()
  def system_metadata do
    {otp_release, elixir_version} = runtime_versions()

    %{
      hostname: hostname(),
      node: to_string(Node.self()),
      elixir_version: elixir_version,
      otp_version: otp_release,
      pid: System.pid()
    }
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "unknown"
    end
  end

  defp runtime_versions do
    otp = :erlang.system_info(:otp_release) |> to_string()
    elixir = System.version()
    {otp, elixir}
  end
end
