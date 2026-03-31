defmodule Mihari.Client do
  @moduledoc """
  GenServer that manages a queue of log entries and flushes them
  to the configured endpoint in batches.

  The client accumulates log entries and sends them when either:
  - The batch size threshold is reached
  - The flush interval timer fires
  - A manual `flush/0` is called
  - The server is shutting down (graceful shutdown)

  ## Usage

  The client is started automatically as part of the Mihari supervision tree.
  Use the public API in `Mihari` to send log entries:

      Mihari.info("Something happened", %{user_id: 42})

  """

  use GenServer

  require Logger

  @type state :: %{
          queue: [Mihari.LogEntry.t()],
          config: Mihari.Config.t(),
          timer_ref: reference() | nil
        }

  # -- Public API --

  @doc """
  Starts the client GenServer linked to the calling process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Enqueues a log entry for sending. The entry will be batched and
  sent according to the configured batch size and flush interval.
  """
  @spec log(Mihari.LogEntry.t(), GenServer.server()) :: :ok
  def log(%Mihari.LogEntry{} = entry, server \\ __MODULE__) do
    GenServer.cast(server, {:log, entry})
  end

  @doc """
  Forces an immediate flush of all queued log entries.
  Returns `{:ok, count}` with the number of entries sent,
  or `{:error, reason}` on failure.
  """
  @spec flush(GenServer.server()) :: {:ok, non_neg_integer()} | {:error, term()}
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, 30_000)
  end

  @doc """
  Returns the number of log entries currently queued.
  """
  @spec queue_size(GenServer.server()) :: non_neg_integer()
  def queue_size(server \\ __MODULE__) do
    GenServer.call(server, :queue_size)
  end

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    config = Mihari.Config.read!()
    timer_ref = schedule_flush(config.flush_interval_ms)

    state = %{
      queue: [],
      config: config,
      timer_ref: timer_ref
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:log, entry}, state) do
    new_queue = [entry | state.queue]

    if length(new_queue) >= state.config.batch_size do
      {result_state, _result} = do_flush(%{state | queue: new_queue})
      {:noreply, result_state}
    else
      {:noreply, %{state | queue: new_queue}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {new_state, result} = do_flush(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:queue_size, _from, state) do
    {:reply, length(state.queue), state}
  end

  @impl true
  def handle_info(:flush_tick, state) do
    {new_state, _result} = do_flush(state)
    timer_ref = schedule_flush(new_state.config.flush_interval_ms)
    {:noreply, %{new_state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.queue != [] do
      Logger.info("[Mihari.Client] Flushing #{length(state.queue)} entries on shutdown")
      do_flush(state)
    end

    :ok
  end

  # -- Private Helpers --

  defp do_flush(%{queue: []} = state), do: {state, {:ok, 0}}

  defp do_flush(%{queue: queue, config: config} = state) do
    entries = Enum.reverse(queue)

    result = Mihari.Transport.send_batch(entries, config)

    case result do
      {:ok, count} ->
        {%{state | queue: []}, {:ok, count}}

      {:error, reason} ->
        Logger.error("[Mihari.Client] Flush failed: #{inspect(reason)}, keeping entries in queue")
        {state, {:error, reason}}
    end
  end

  defp schedule_flush(interval_ms) do
    Process.send_after(self(), :flush_tick, interval_ms)
  end
end
