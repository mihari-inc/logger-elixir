import Config

config :mihari,
  endpoint: "http://localhost:4001/api/v1/logs",
  token: "test-token",
  batch_size: 3,
  flush_interval_ms: 100,
  max_retries: 1,
  retry_base_delay_ms: 10,
  gzip: false

config :logger, level: :warning
