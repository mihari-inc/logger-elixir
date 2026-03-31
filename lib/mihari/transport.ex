defmodule Mihari.Transport do
  @moduledoc """
  HTTP transport layer responsible for sending batches of log entries
  to the configured endpoint.

  Handles JSON encoding, optional gzip compression, authentication,
  and retry logic with exponential backoff.
  """

  require Logger

  @doc """
  Sends a list of log entries to the configured endpoint.

  Returns `{:ok, count}` on success (HTTP 202) where `count` is the
  number of entries accepted, or `{:error, reason}` after exhausting
  all retry attempts.

  ## Parameters

    * `entries` - List of `%Mihari.LogEntry{}` structs to send
    * `config` - `%Mihari.Config{}` struct with endpoint, token, etc.

  """
  @spec send_batch([Mihari.LogEntry.t()], Mihari.Config.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def send_batch([], _config), do: {:ok, 0}

  def send_batch(entries, %Mihari.Config{} = config) do
    payload = entries |> Enum.map(&Mihari.LogEntry.to_map/1)

    case Jason.encode(payload) do
      {:ok, json} ->
        do_send_with_retries(json, config, 0)

      {:error, reason} ->
        Logger.error("[Mihari.Transport] JSON encode error: #{inspect(reason)}")
        {:error, {:json_encode, reason}}
    end
  end

  defp do_send_with_retries(json, config, attempt) do
    {body, headers} = prepare_body_and_headers(json, config)

    case Req.post(config.endpoint, body: body, headers: headers, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 202, body: resp_body}} ->
        count = parse_accepted_count(resp_body)
        {:ok, count}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        handle_failure(json, config, attempt, {:http_error, status, resp_body})

      {:error, reason} ->
        handle_failure(json, config, attempt, {:request_error, reason})
    end
  end

  defp handle_failure(json, config, attempt, error) do
    if attempt < config.max_retries do
      delay = backoff_delay(attempt, config.retry_base_delay_ms)

      Logger.warning(
        "[Mihari.Transport] Attempt #{attempt + 1} failed: #{inspect(error)}, " <>
          "retrying in #{delay}ms"
      )

      Process.sleep(delay)
      do_send_with_retries(json, config, attempt + 1)
    else
      Logger.error(
        "[Mihari.Transport] All #{config.max_retries + 1} attempts failed: #{inspect(error)}"
      )

      {:error, error}
    end
  end

  defp prepare_body_and_headers(json, config) do
    base_headers = [
      {"content-type", "application/json"},
      {"user-agent", "mihari-elixir/#{Application.spec(:mihari, :vsn) || "dev"}"}
    ]

    auth_headers =
      if config.token do
        [{"authorization", "Bearer #{config.token}"}]
      else
        []
      end

    {body, encoding_headers} =
      if config.gzip do
        compressed = :zlib.gzip(json)
        {compressed, [{"content-encoding", "gzip"}]}
      else
        {json, []}
      end

    {body, base_headers ++ auth_headers ++ encoding_headers}
  end

  defp parse_accepted_count(%{"count" => count}) when is_integer(count), do: count
  defp parse_accepted_count(%{"count" => count}) when is_binary(count), do: String.to_integer(count)
  defp parse_accepted_count(_), do: 0

  @doc false
  def backoff_delay(attempt, base_delay_ms) do
    # Exponential backoff with jitter: base * 2^attempt + random(0..base)
    base = base_delay_ms * Integer.pow(2, attempt)
    jitter = :rand.uniform(base_delay_ms)
    base + jitter
  end
end
