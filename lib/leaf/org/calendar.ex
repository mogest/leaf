defmodule Leaf.Org.Calendar do
  @moduledoc """
  A country, or a region within one: whose public holidays somebody observes and where they are.

  A region holds only what is local to it, and whoever is on it observes its country's holidays as
  well, so a national list is entered once however many regions sit inside it (§4.9). What country
  a region is in and what zone it keeps come from the country it is created under, so adding one is
  a name and, where it differs, a zone.
  """

  use Leaf.Schema

  alias Leaf.Org.Organisation

  @type t :: %__MODULE__{}

  @fields [:name, :country_code, :time_zone]

  schema "calendars" do
    field :name, :string
    field :country_code, :string
    field :time_zone, :string

    belongs_to :organisation, Organisation
    belongs_to :parent, __MODULE__
    has_many :regions, __MODULE__, foreign_key: :parent_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(calendar, attrs) do
    calendar
    |> cast(attrs, @fields)
    |> validate_required([:organisation_id | @fields])
    |> validate_length(:country_code, is: 2)
    |> validate_time_zone()
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:parent)
  end

  # The zone is only as good as the database can resolve it, and a zone that resolves to nothing is
  # a date shown wrong rather than an error anybody would see.
  defp validate_time_zone(changeset) do
    validate_change(changeset, :time_zone, fn :time_zone, zone ->
      case DateTime.now(zone) do
        {:ok, _now} -> []
        {:error, _reason} -> [time_zone: "is not a time zone"]
      end
    end)
  end
end
