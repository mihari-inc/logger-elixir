defmodule Mihari.LogEntry do
  @moduledoc """
  Represents a single structured log entry.

  Each entry contains a timestamp, severity level, message, and optional
  metadata. System metadata (hostname, node, runtime versions) is merged
  automatically at creation time.

  ## Fields

    * `:dt` - ISO 8601 timestamp string
    * `:level` - Log severity: `"info"`, `"warn"`, `"error"`, `"debug"`, or `"fatal"`
    * `:message` - The log message
    * `:metadata` - Additional key-value metadata

  """

  @type level :: :info | :warn | :error | :debug | :fatal

  @type t :: %__MODULE__{
          dt: String.t(),
          level: String.t(),
          message: String.t(),
          metadata: map()
        }

  @enforce_keys [:dt, :level, :message]
  defstruct [:dt, :level, :message, metadata: %{}]

  @valid_levels ~w(info warn error debug fatal)a

  @doc """
  Creates a new log entry with the current timestamp and system metadata.

  ## Parameters

    * `level` - One of `:info`, `:warn`, `:error`, `:debug`, `:fatal`
    * `message` - The log message string
    * `metadata` - Optional map of extra metadata (default: `%{}`)

  ## Examples

      iex> entry = Mihari.LogEntry.new(:info, "User signed in", %{user_id: 42})
      iex> entry.level
      "info"
      iex> entry.message
      "User signed in"

  """
  @spec new(level(), String.t(), map()) :: t()
  def new(level, message, metadata \\ %{}) when level in @valid_levels do
    system_meta = Mihari.Config.system_metadata()

    %__MODULE__{
      dt: DateTime.utc_now() |> DateTime.to_iso8601(),
      level: to_string(level),
      message: to_string(message),
      metadata: Map.merge(system_meta, metadata)
    }
  end

  @doc """
  Converts a log entry to a plain map suitable for JSON encoding.

  Metadata fields are flattened into the top-level map alongside
  `dt`, `level`, and `message`.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = entry) do
    %{
      dt: entry.dt,
      level: entry.level,
      message: entry.message
    }
    |> Map.merge(stringify_keys(entry.metadata))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
