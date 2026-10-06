defmodule Leaf.DataCase do
  @moduledoc """
  The test case for tests requiring access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Leaf.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Leaf.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Leaf.DataCase
    end
  end

  setup tags do
    Leaf.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc "Sets up the sandbox based on the test tags."
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Leaf.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    on_exit(&await_messages/0)
  end

  @doc """
  Waits for every message Leaf is sending to have been sent.

  A write sends its messages from a task of its own, which reads and writes through the test's
  sandbox, so it has to be done before anything is asserted of them or the sandbox goes.
  """
  def await_messages do
    for pid <- Task.Supervisor.children(Leaf.Messaging.Tasks) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, _pid, _reason} -> :ok
      after
        1_000 -> raise "a message was still being sent after a second"
      end
    end

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Leave.create_balance_entry(person, nil, %{amount: nil})
      assert "can't be blank" in errors_on(changeset).amount

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
