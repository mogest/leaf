defmodule Leaf.Audit do
  @moduledoc """
  The record of who changed what.

  Grants, accruals and expiries are not here. Nobody performs them — they follow from a person's
  dates, hours and policy — so they belong to the leave history. What is here is the change that
  caused them, and who made it.

  Every write somebody makes goes through `write/4`, which puts the change and the entry
  accounting for it in one transaction, so a change cannot be recorded without being explained.
  """

  alias Ecto.Association.NotLoaded
  alias Ecto.Changeset
  alias Ecto.Multi
  alias Leaf.Audit.Entry
  alias Leaf.People.Person
  alias Leaf.Repo

  @doc """
  Applies a change and records it.

  `subject_person_id` is whose record the change was about, and is what survives the row being
  deleted; leave it out where the change was about nobody in particular, such as editing a leave
  type. The entry holds a before and an after for each field the changeset touched.
  """
  @spec write(Changeset.t(), String.t(), Person.t(), Ecto.UUID.t() | nil) ::
          {:ok, struct()} | {:error, Changeset.t()}
  def write(changeset, action, actor, subject_person_id \\ nil) do
    Multi.new()
    |> Multi.insert_or_update(:record, changeset)
    |> Multi.insert(:entry, &entry(&1.record, changeset, action, actor, subject_person_id))
    |> Repo.transaction()
    |> outcome()
  end

  defp outcome({:ok, %{record: record}}), do: {:ok, record}
  defp outcome({:error, :record, changeset, _changes}), do: {:error, changeset}

  defp outcome({:error, :entry, changeset, _changes}) do
    raise "audit entry refused: #{inspect(changeset.errors)}"
  end

  defp entry(record, changeset, action, actor, subject_person_id) do
    Entry.changeset(%Entry{}, %{
      actor_id: actor.id,
      subject_person_id: subject_person_id,
      action: action,
      entity_type: record.__struct__.__schema__(:source),
      entity_id: record.id,
      changes: changes(changeset)
    })
  end

  defp changes(changeset) do
    Map.new(changeset.changes, fn {field, value} ->
      {field, %{from: previous(changeset.data, field), to: recorded(value)}}
    end)
  end

  # A row that does not exist yet has nothing to have been, which is not the same as an
  # association nobody bothered to load.
  defp previous(%{__meta__: %{state: :built}}, _field), do: nil
  defp previous(data, field), do: recorded(Map.get(data, field))

  defp recorded(nil), do: nil
  defp recorded(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value

  defp recorded(%Changeset{} = changeset),
    do: changeset |> Changeset.apply_changes() |> recorded()

  defp recorded(%{__meta__: %Ecto.Schema.Metadata{}} = record), do: record_fields(record)

  defp recorded(%NotLoaded{__field__: field}) do
    raise "#{field} must be loaded before a change to it can be recorded"
  end

  # A has_many keeps the rows it is dropping in the changeset, so that they are deleted. They are
  # what the change is from, not what it is to.
  defp recorded(values) when is_list(values) do
    values |> Enum.reject(&dropped?/1) |> Enum.map(&recorded/1)
  end

  defp recorded(value), do: to_string(value)

  defp record_fields(%module{} = record) do
    module.__schema__(:fields)
    |> Kernel.--([:inserted_at, :updated_at])
    |> Map.new(&{&1, recorded(Map.get(record, &1))})
  end

  defp dropped?(%Changeset{action: action}), do: action in [:replace, :delete]
  defp dropped?(_value), do: false
end
