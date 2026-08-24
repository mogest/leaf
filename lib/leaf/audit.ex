defmodule Leaf.Audit do
  @moduledoc """
  The record of who changed what.

  Grants, accruals and expiries are not here. Nobody performs them — they follow from a person's
  dates, hours and policy — so they belong to the leave history. What is here is the change that
  caused them, and who made it.

  Every write somebody makes goes through `write/4` or `delete/4`, which put the change and the
  entry accounting for it in one transaction, so a change cannot be recorded without being
  explained.

  An `actor` of `nil` is the system itself, which is what a seed or an import is: nobody made the
  change, so there is nobody to name.
  """

  import Ecto.Query

  alias Ecto.Association.NotLoaded
  alias Ecto.Changeset
  alias Ecto.Multi
  alias Leaf.Audit.Entry
  alias Leaf.People.Person
  alias Leaf.Repo

  @typedoc "What a recorded write returns: the record it wrote, or why it would not."
  @type written(record) :: {:ok, record} | {:error, Changeset.t()}

  @doc """
  Applies a change and records it.

  `subject_person_id` is whose record the change was about, and is what survives the row being
  deleted; leave it out where the change was about nobody in particular, such as editing a leave
  type. The entry holds a before and an after for each field the changeset touched.
  """
  @spec write(Changeset.t(), String.t(), Person.t() | nil, Ecto.UUID.t() | nil) ::
          written(struct())
  def write(changeset, action, actor, subject_person_id \\ nil) do
    Multi.new()
    |> Multi.insert_or_update(:record, changeset)
    |> record(changeset, action, actor, subject_person_id)
    |> Repo.transaction()
    |> outcome()
  end

  @doc """
  Removes a row and records the whole of what it held.

  A hard-deleted record survives in its entry and nowhere else, so everything it held is recorded
  on the way out rather than only what someone chose to look at.
  """
  @spec delete(struct(), String.t(), Person.t() | nil, Ecto.UUID.t() | nil) ::
          written(struct())
  def delete(record, action, actor, subject_person_id \\ nil) do
    Multi.new()
    |> Multi.delete(:record, record)
    |> Multi.insert(:entry, entry(record, removal(record), action, actor, subject_person_id))
    |> Repo.transaction()
    |> outcome()
  end

  @doc "The most recently recorded entries, newest first, with who acted and who it was about."
  @spec entries(pos_integer()) :: [Entry.t()]
  def entries(limit), do: Repo.all(newest_first(limit))

  @doc "The same, narrowed to the changes recorded about one person."
  @spec entries(Person.t(), pos_integer()) :: [Entry.t()]
  def entries(person, limit) do
    Repo.all(from entry in newest_first(limit), where: entry.subject_person_id == ^person.id)
  end

  defp newest_first(limit) do
    from entry in Entry,
      order_by: [desc: entry.inserted_at],
      limit: ^limit,
      preload: [:actor, :subject_person]
  end

  defp outcome({:ok, %{record: record}}), do: {:ok, record}
  defp outcome({:error, :record, changeset, _changes}), do: {:error, changeset}

  defp outcome({:error, :entry, changeset, _changes}) do
    raise "audit entry refused: #{inspect(changeset.errors)}"
  end

  # Saving a form unchanged is not an action anybody took: there is no before and no after to
  # record, and an entry saying so is noise in the log.
  defp record(multi, %Changeset{changes: changes}, _action, _actor, _subject_person_id)
       when changes == %{},
       do: multi

  defp record(multi, changeset, action, actor, subject_person_id) do
    Multi.insert(
      multi,
      :entry,
      &entry(&1.record, changes(changeset, &1.record), action, actor, subject_person_id)
    )
  end

  defp entry(record, changes, action, actor, subject_person_id) do
    Entry.changeset(%Entry{}, %{
      actor_id: actor && actor.id,
      subject_person_id: subject_person_id,
      action: action,
      entity_type: record.__struct__.__schema__(:source),
      entity_id: record.id,
      changes: changes
    })
  end

  defp removal(record) do
    Map.new(record_fields(record), fn {field, value} -> {field, %{from: value, to: nil}} end)
  end

  # What a field became is read off the written row rather than off the changeset, so that rows
  # created alongside it are named by the ids they were given.
  defp changes(changeset, record) do
    Map.new(changeset.changes, fn {field, _value} ->
      {field, %{from: previous(changeset.data, field), to: recorded(Map.get(record, field))}}
    end)
  end

  # A row that does not exist yet has nothing to have been, which is not the same as an
  # association nobody bothered to load.
  defp previous(%{__meta__: %{state: :built}}, _field), do: nil
  defp previous(data, field), do: recorded(Map.get(data, field))

  defp recorded(nil), do: nil
  defp recorded(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value

  defp recorded(%{__meta__: %Ecto.Schema.Metadata{}} = record), do: record_fields(record)

  defp recorded(%NotLoaded{__field__: field}) do
    raise "#{field} must be loaded before a change to it can be recorded"
  end

  defp recorded(values) when is_list(values), do: Enum.map(values, &recorded/1)

  defp recorded(value), do: to_string(value)

  defp record_fields(%module{} = record) do
    module.__schema__(:fields)
    |> Kernel.--([:inserted_at, :updated_at])
    |> Map.new(&{&1, recorded(Map.get(record, &1))})
  end
end
