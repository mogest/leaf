defmodule Leaf.Release do
  @moduledoc "Database release tasks, run in production where Mix is not installed."

  @app :leaf

  @spec migrate() :: :ok
  def migrate do
    each_repo(&Ecto.Migrator.run(&1, :up, all: true))
  end

  @spec rollback(integer()) :: :ok
  def rollback(version) do
    each_repo(&Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Raises, naming the pending migrations, unless every migration has been run."
  @spec check_migrated() :: :ok
  def check_migrated do
    each_repo(fn repo ->
      pending = for {:down, version, _name} <- Ecto.Migrator.migrations(repo), do: version

      if pending != [] do
        raise "#{inspect(repo)} has pending migrations #{Enum.join(pending, ", ")}; run bin/migrate first"
      end
    end)
  end

  defp each_repo(fun) do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fun)
    end

    :ok
  end
end
