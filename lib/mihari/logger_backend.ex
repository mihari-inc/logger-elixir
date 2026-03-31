defmodule Mihari.LoggerBackend do
  @moduledoc """
  An Elixir Logger backend that forwards log messages to Mihari.

  This module implements the `:gen_event` behaviour required by
  Elixir's Logger. When installed, all log messages at or above
  the configured level are automatically forwarded to the Mihari
  client for batching and transport.

  ## Installation

  Add to your Logger backends in `config/config.exs`:

      config :logger,
        backends: [:console, Mihari.LoggerBackend]

  ## Configuration

      config :logger, Mihari.LoggerBackend,
        level: :info,
        metadata: :all

  ## Options

    * `:level` - Minimum log level to forward (default: `:info`)
    * `:metadata` - Which metadata keys to include. Either `:all` or
      a list of atom keys (default: `:all`)

  """

  @behaviour :gen_event

  @type state :: %{
          level: Logger.level(),
          metadata: :all | [atom()]
        }

  @impl true
  def init(__MODULE__) do
    config = Application.get_env(:logger, __MODULE__, [])

    state = %{
      level: Keyword.get(config, :level, :info),
      metadata: Keyword.get(config, :metadata, :all)
    }

    {:ok, state}
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    state = %{
      level: Keyword.get(opts, :level, :info),
      metadata: Keyword.get(opts, :metadata, :all)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:configure, opts}, state) do
    new_state = %{
      level: Keyword.get(opts, :level, state.level),
      metadata: Keyword.get(opts, :metadata, state.metadata)
    }

    {:ok, :ok, new_state}
  end

  @impl true
  def handle_event({level, _gl, {Logger, message, timestamp, metadata}}, state) do
    if meet_level?(level, state.level) do
      forward_log(level, message, timestamp, metadata, state)
    end

    {:ok, state}
  end

  @impl true
  def handle_event(:flush, state) do
    try do
      Mihari.Client.flush()
    catch
      _, _ -> :ok
    end

    {:ok, state}
  end

  @impl true
  def handle_event(_, state), do: {:ok, state}

  @impl true
  def handle_info(_, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  # -- Private --

  defp forward_log(level, message, _timestamp, metadata, state) do
    mihari_level = normalize_level(level)
    meta = filter_metadata(metadata, state.metadata)

    msg =
      case message do
        msg when is_binary(msg) -> msg
        msg when is_list(msg) -> IO.chardata_to_string(msg)
        msg -> inspect(msg)
      end

    entry = Mihari.LogEntry.new(mihari_level, msg, meta)

    try do
      Mihari.Client.log(entry)
    catch
      _, _ -> :ok
    end
  end

  defp normalize_level(:warning), do: :warn
  defp normalize_level(:warn), do: :warn
  defp normalize_level(:emergency), do: :fatal
  defp normalize_level(:alert), do: :fatal
  defp normalize_level(:critical), do: :fatal
  defp normalize_level(level), do: level

  defp meet_level?(msg_level, min_level) do
    Logger.compare_levels(msg_level, min_level) != :lt
  end

  defp filter_metadata(metadata, :all) do
    metadata
    |> Enum.reject(fn {k, _v} -> k in [:gl, :pid, :erl_level] end)
    |> Map.new(fn {k, v} -> {k, inspect_if_needed(v)} end)
  end

  defp filter_metadata(metadata, keys) when is_list(keys) do
    metadata
    |> Enum.filter(fn {k, _v} -> k in keys end)
    |> Map.new(fn {k, v} -> {k, inspect_if_needed(v)} end)
  end

  defp inspect_if_needed(v) when is_binary(v), do: v
  defp inspect_if_needed(v) when is_number(v), do: v
  defp inspect_if_needed(v) when is_boolean(v), do: v
  defp inspect_if_needed(v) when is_atom(v), do: to_string(v)
  defp inspect_if_needed(v), do: inspect(v)
end
