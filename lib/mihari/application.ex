defmodule Mihari.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Mihari.Client, []}
    ]

    opts = [strategy: :one_for_one, name: Mihari.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
