defmodule Leaf.Org do
  @moduledoc """
  The organisation, its working-week conventions, and the calendars its people are on.

  A calendar is a country or a region within one (§4.9), and holds only its own holidays: what
  somebody on it observes is those and its country's together, which is `observed_holidays/2` and
  the reason nothing else reads the holidays of a calendar it did not ask about.

  Nothing here belongs to a person, so its audit entries name no subject. Moving `tracked_from` is
  the one change that re-works every balance in the organisation at once (§4.10), which is why it
  goes through the same recorded path as everything else.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Org.Calendar
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
  alias Leaf.Org.TimeZones
  alias Leaf.People.Person
  alias Leaf.Repo

  @doc "Creates an organisation."
  @spec create_organisation(Person.t() | nil, map()) :: Audit.written(Organisation.t())
  def create_organisation(actor, attrs) do
    %Organisation{} |> Organisation.changeset(attrs) |> Audit.write("organisation.created", actor)
  end

  @doc "The changeset an organisation's form binds to."
  @spec change_organisation(Organisation.t(), map()) :: Ecto.Changeset.t()
  def change_organisation(organisation, attrs), do: Organisation.changeset(organisation, attrs)

  @doc "The changeset a country's form binds to: a new one, or one the organisation holds."
  @spec change_calendar(Organisation.t() | Calendar.t(), map()) :: Ecto.Changeset.t()
  def change_calendar(%Organisation{} = organisation, attrs) do
    Calendar.changeset(%Calendar{organisation_id: organisation.id}, attrs)
  end

  def change_calendar(%Calendar{} = calendar, attrs), do: Calendar.changeset(calendar, attrs)

  @doc "The changeset a new region's form binds to, opening on its country's country and zone."
  @spec change_region(Calendar.t(), map()) :: Ecto.Changeset.t()
  def change_region(%Calendar{} = country, attrs),
    do: Calendar.changeset(region_of(country), attrs)

  @doc "The changeset a public holiday's form binds to."
  @spec change_public_holiday(Calendar.t() | PublicHoliday.t(), map()) :: Ecto.Changeset.t()
  def change_public_holiday(%Calendar{} = calendar, attrs) do
    PublicHoliday.changeset(%PublicHoliday{calendar_id: calendar.id}, attrs)
  end

  def change_public_holiday(%PublicHoliday{} = holiday, attrs) do
    PublicHoliday.changeset(holiday, attrs)
  end

  @doc "Amends an organisation."
  @spec update_organisation(Organisation.t(), Person.t() | nil, map()) ::
          Audit.written(Organisation.t())
  def update_organisation(organisation, actor, attrs) do
    organisation
    |> Organisation.changeset(attrs)
    |> Audit.write("organisation.updated", actor)
  end

  @doc "Every organisation, oldest first."
  @spec organisations() :: [Organisation.t()]
  def organisations, do: Repo.all(from o in Organisation, order_by: o.inserted_at)

  @doc "The organisation, or `:error` where no such organisation exists."
  @spec fetch_organisation(Ecto.UUID.t()) :: {:ok, Organisation.t()} | :error
  def fetch_organisation(id), do: Repo.fetch(Organisation, id)

  @doc """
  Every calendar the organisation holds, each with the country it is in, by name.

  Countries are in name order and each is followed by its own regions, so a list of them reads as
  the shape they are in.
  """
  @spec calendars(Ecto.UUID.t()) :: [Calendar.t()]
  def calendars(organisation_id) do
    Repo.all(
      from calendar in Calendar,
        left_join: country in assoc(calendar, :parent),
        where: calendar.organisation_id == ^organisation_id,
        order_by: [
          asc: coalesce(country.name, calendar.name),
          asc_nulls_first: calendar.parent_id,
          asc: calendar.name
        ],
        preload: [parent: country]
    )
  end

  @doc "The time zones a calendar in a country might keep, for it to be offered a choice of."
  @spec time_zones(String.t() | nil) :: [String.t()]
  defdelegate time_zones(country_code), to: TimeZones, as: :of

  @doc "The calendar, with the country and regions around it, or `:error` where there is none."
  @spec fetch_calendar(Ecto.UUID.t()) :: {:ok, Calendar.t()} | :error
  def fetch_calendar(id) do
    with {:ok, calendar} <- Repo.fetch(Calendar, id) do
      {:ok,
       Repo.preload(calendar, [:parent, regions: from(region in Calendar, order_by: region.name)])}
    end
  end

  @doc "One of the calendar's public holidays, or `:error` where it is not on it."
  @spec fetch_public_holiday(Calendar.t(), Ecto.UUID.t()) :: {:ok, PublicHoliday.t()} | :error
  def fetch_public_holiday(calendar, id) do
    Repo.fetch(PublicHoliday, id, calendar_id: calendar.id)
  end

  @doc "Creates a country's calendar."
  @spec create_calendar(Organisation.t(), Person.t() | nil, map()) :: Audit.written(Calendar.t())
  def create_calendar(organisation, actor, attrs) do
    %Calendar{organisation_id: organisation.id}
    |> Calendar.changeset(attrs)
    |> Audit.write("calendar.created", actor)
  end

  @doc """
  Creates a region within a country.

  Its country and its zone are the country's until it says otherwise, so a region that keeps both —
  most of them — is a name. A region of a region is not a shape the model has.
  """
  @spec create_region(Calendar.t(), Person.t() | nil, map()) :: Audit.written(Calendar.t())
  def create_region(%Calendar{} = country, actor, attrs) do
    country |> region_of() |> Calendar.changeset(attrs) |> Audit.write("calendar.created", actor)
  end

  @doc """
  Amends a calendar.

  A region does not follow its country here. Its country code and zone were taken when it was
  created and are its own from then, so a country that moves zone leaves its regions to be moved
  after it.
  """
  @spec update_calendar(Calendar.t(), Person.t() | nil, map()) :: Audit.written(Calendar.t())
  def update_calendar(calendar, actor, attrs) do
    calendar |> Calendar.changeset(attrs) |> Audit.write("calendar.updated", actor)
  end

  @doc "Adds one public holiday to a calendar."
  @spec create_public_holiday(Calendar.t(), Person.t() | nil, map()) ::
          Audit.written(PublicHoliday.t())
  def create_public_holiday(calendar, actor, attrs) do
    %PublicHoliday{calendar_id: calendar.id}
    |> PublicHoliday.changeset(attrs)
    |> Audit.write("public_holiday.created", actor)
  end

  @doc "Amends one public holiday."
  @spec update_public_holiday(PublicHoliday.t(), Person.t() | nil, map()) ::
          Audit.written(PublicHoliday.t())
  def update_public_holiday(holiday, actor, attrs) do
    holiday
    |> PublicHoliday.changeset(attrs)
    |> Audit.write("public_holiday.updated", actor)
  end

  @doc """
  Removes one public holiday from a calendar.

  A holiday entered in error would otherwise keep counting against every public holiday allowance
  drawn from its calendar, so it goes rather than being superseded.
  """
  @spec delete_public_holiday(PublicHoliday.t(), Person.t() | nil) ::
          Audit.written(PublicHoliday.t())
  def delete_public_holiday(holiday, actor) do
    Audit.delete(holiday, "public_holiday.deleted", actor)
  end

  @doc "The public holidays entered on a calendar itself, in date order."
  @spec public_holidays(Ecto.UUID.t()) :: [PublicHoliday.t()]
  def public_holidays(calendar_id) do
    Repo.all(
      from holiday in PublicHoliday,
        where: holiday.calendar_id == ^calendar_id,
        order_by: holiday.date
    )
  end

  @doc """
  Every public holiday somebody on a calendar observes, in date order.

  A region observes its country's holidays as well as its own, and cannot decline one of them.
  """
  @spec observed_holidays(Ecto.UUID.t()) :: [PublicHoliday.t()]
  def observed_holidays(calendar_id), do: Repo.all(observed(calendar_id))

  @doc "The same, within `range`."
  @spec observed_holidays(Ecto.UUID.t(), Date.Range.t()) :: [PublicHoliday.t()]
  def observed_holidays(calendar_id, range) do
    Repo.all(
      from holiday in observed(calendar_id),
        where: holiday.date >= ^range.first and holiday.date <= ^range.last
    )
  end

  # A region that enters a day its country already keeps is still one day off, and an allowance that
  # counted it twice would be worth two. So a date is observed once, under the nearer of the two
  # names for it.
  defp observed(calendar_id) do
    from holiday in PublicHoliday,
      join: calendar in Calendar,
      on: calendar.id == ^calendar_id,
      where: holiday.calendar_id in [calendar.id, calendar.parent_id],
      distinct: holiday.date,
      order_by: [asc: holiday.date, desc: holiday.calendar_id == ^calendar_id]
  end

  defp region_of(%Calendar{parent_id: nil} = country) do
    %Calendar{
      organisation_id: country.organisation_id,
      parent_id: country.id,
      country_code: country.country_code,
      time_zone: country.time_zone
    }
  end
end
