# Mihari Logger

Open-source log collection and transport library for Elixir. Ship structured logs to any HTTP endpoint with automatic batching, gzip compression, retries with exponential backoff, and a native Elixir Logger backend.

## Features

- Structured JSON log entries with automatic metadata (hostname, node, Elixir/OTP version)
- Configurable batching (default: 10 entries per batch)
- Periodic flush interval (default: 5 seconds)
- Gzip compression via `:zlib`
- Retry with exponential backoff and jitter
- Elixir Logger backend for zero-code integration
- Graceful shutdown with queue flush
- OTP supervision tree

## Installation

Add `mihari_logger` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mihari_logger, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :mihari_logger,
  endpoint: "https://logs.example.com/api/v1/logs",
  token: System.get_env("MIHARI_TOKEN"),
  batch_size: 10,
  flush_interval_ms: 5_000,
  max_retries: 3,
  retry_base_delay_ms: 1_000,
  gzip: true
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `endpoint` | string | **required** | HTTP endpoint URL |
| `token` | string | `nil` | Bearer token for Authorization header |
| `batch_size` | integer | `10` | Entries per batch before auto-flush |
| `flush_interval_ms` | integer | `5000` | Milliseconds between periodic flushes |
| `max_retries` | integer | `3` | Retry attempts on failure |
| `retry_base_delay_ms` | integer | `1000` | Base delay for exponential backoff |
| `gzip` | boolean | `true` | Compress payloads with gzip |

## Usage

### Direct API

```elixir
# Basic logging
Mihari.info("User signed in", %{user_id: 42})
Mihari.warn("Disk usage high", %{percent: 92})
Mihari.error("Payment failed", %{order_id: "abc-123", reason: "timeout"})
Mihari.debug("Cache miss", %{key: "user:42:profile"})
Mihari.fatal("System out of memory", %{available_mb: 12})

# Force immediate flush
{:ok, count} = Mihari.flush()

# Check queue size
size = Mihari.queue_size()
```

### Logger Backend

Install the backend to automatically forward all Elixir Logger messages:

```elixir
# config/config.exs
config :logger,
  backends: [:console, Mihari.LoggerBackend]

config :logger, Mihari.LoggerBackend,
  level: :info,
  metadata: :all
```

Then standard Logger calls are automatically forwarded:

```elixir
require Logger

Logger.info("Request completed", duration_ms: 42, path: "/api/users")
Logger.error("Database timeout", host: "db-primary")
```

## Phoenix Integration

### Setup

Add Mihari to your Phoenix application dependencies and configure it:

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:mihari_logger, "~> 0.1.0"},
    # ... other deps
  ]
end
```

```elixir
# config/config.exs
config :mihari_logger,
  endpoint: "https://logs.example.com/api/v1/logs",
  token: System.get_env("MIHARI_TOKEN")
```

### Request Logging Plug

Create a Plug to capture request metadata:

```elixir
defmodule MyAppWeb.Plugs.MihariLogger do
  @behaviour Plug

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time(:millisecond) - start_time

      metadata = %{
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: duration,
        remote_ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
        request_id: get_resp_header(conn, "x-request-id") |> List.first()
      }

      level = if conn.status >= 500, do: :error, else: :info
      apply(Mihari, level, ["HTTP #{conn.method} #{conn.request_path} #{conn.status}", metadata])

      conn
    end)
  end
end
```

Add it to your router pipeline:

```elixir
# lib/my_app_web/router.ex
pipeline :api do
  plug :accepts, ["json"]
  plug MyAppWeb.Plugs.MihariLogger
end
```

### Error Reporting in Controllers

```elixir
defmodule MyAppWeb.FallbackController do
  use MyAppWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    Mihari.warn("Validation failed", %{
      path: conn.request_path,
      errors: inspect(changeset.errors)
    })

    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render(:"422")
  end

  def call(conn, {:error, reason}) do
    Mihari.error("Unhandled error", %{
      path: conn.request_path,
      reason: inspect(reason)
    })

    conn
    |> put_status(:internal_server_error)
    |> put_view(json: MyAppWeb.ErrorJSON)
    |> render(:"500")
  end
end
```

### LiveView Logging

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view

  def mount(_params, session, socket) do
    Mihari.info("LiveView mounted", %{
      view: "DashboardLive",
      user_id: session["user_id"]
    })

    {:ok, socket}
  end

  def handle_event("refresh", _params, socket) do
    Mihari.debug("Dashboard refresh", %{view: "DashboardLive"})
    {:noreply, socket}
  end
end
```

### Oban Job Logging

```elixir
defmodule MyApp.Workers.EmailWorker do
  use Oban.Worker, queue: :mailers

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"to" => to, "template" => template}} = job) do
    Mihari.info("Sending email", %{
      job_id: job.id,
      to: to,
      template: template,
      attempt: job.attempt
    })

    case MyApp.Mailer.deliver(to, template) do
      {:ok, _} ->
        Mihari.info("Email sent", %{job_id: job.id, to: to})
        :ok

      {:error, reason} ->
        Mihari.error("Email delivery failed", %{
          job_id: job.id,
          to: to,
          reason: inspect(reason),
          attempt: job.attempt
        })

        {:error, reason}
    end
  end
end
```

## Log Entry Format

Each log entry is sent as JSON with the following structure:

```json
{
  "dt": "2026-03-31T12:00:00.000000Z",
  "level": "info",
  "message": "User signed in",
  "hostname": "web-01",
  "node": "myapp@web-01",
  "elixir_version": "1.16.0",
  "otp_version": "26",
  "pid": "12345",
  "user_id": 42
}
```

Custom metadata keys are flattened into the top-level object alongside the standard fields.

## API Protocol

Mihari sends batched log entries as a JSON array via HTTP POST:

- **Authorization**: `Bearer <token>`
- **Content-Type**: `application/json`
- **Content-Encoding**: `gzip` (when enabled)
- **Expected Response**: HTTP 202 with `{"status": "accepted", "count": N}`

## Architecture

Mihari uses an OTP supervision tree:

```
Mihari.Supervisor
  └── Mihari.Client (GenServer)
        ├── Accumulates log entries in memory
        ├── Flushes on batch size threshold
        ├── Flushes on periodic timer
        └── Flushes on shutdown (terminate/2)
```

The `Mihari.Transport` module handles HTTP communication with retry logic and optional gzip compression.

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover

# Format code
mix format

# Generate docs
mix docs
```

## License

MIT License. See [LICENSE](LICENSE) for details.
