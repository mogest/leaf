defmodule Leaf.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = :logger.add_handler(:sentry, Sentry.LoggerHandler, %{})

    children = [
      Leaf.Repo,
      {Phoenix.PubSub, name: Leaf.PubSub},
      LeafWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Leaf.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LeafWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
