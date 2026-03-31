import Config

config :mihari,
  endpoint: System.get_env("MIHARI_ENDPOINT", "https://logs.mihari.io/api/v1/logs"),
  token: System.get_env("MIHARI_TOKEN"),
  batch_size: 10,
  flush_interval_ms: 5_000,
  max_retries: 3,
  retry_base_delay_ms: 1_000,
  gzip: true

import_config "#{config_env()}.exs"
