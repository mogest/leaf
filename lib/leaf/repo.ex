defmodule Leaf.Repo do
  use Ecto.Repo,
    otp_app: :leaf,
    adapter: Ecto.Adapters.Postgres
end
