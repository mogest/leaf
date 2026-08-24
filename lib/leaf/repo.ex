defmodule Leaf.Repo do
  use Ecto.Repo,
    otp_app: :leaf,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Whether the database is answering.

  A pod that has lost its database can serve nothing, and a probe has to be told so rather than
  raised at, so a connection that is gone entirely reads the same as a query that failed.
  """
  @spec reachable?() :: boolean()
  def reachable? do
    match?({:ok, _result}, query("SELECT 1"))
  rescue
    _error -> false
  end

  @doc """
  The row with that id, or `:error` where none has it.

  Ids reach this from the URL, so one that could not name a row whatever the database holds —
  anything that is not a UUID — answers the same as one that names none rather than raising.

  `within` scopes the lookup to the parent the row hangs off, so an id belonging to somebody
  else reads as missing rather than as theirs.
  """
  @spec fetch(module(), term(), keyword()) :: {:ok, struct()} | :error
  def fetch(schema, id, within \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> schema |> get_by([{:id, id} | within]) |> found()
      :error -> :error
    end
  end

  defp found(nil), do: :error
  defp found(record), do: {:ok, record}
end
