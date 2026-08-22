defmodule Leaf.Org do
  @moduledoc """
  The organisation, its working-week conventions, and its public holiday calendars.

  Nothing here belongs to a person, so its audit entries name no subject. Moving `tracked_from` is
  the one change that re-works every balance in the organisation at once (§4.10), which is why it
  goes through the same recorded path as everything else.
  """

  import Ecto.Query

  alias Leaf.Audit
  alias Leaf.Org.HolidayCalendar
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
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

  @doc "The changeset a holiday calendar's form binds to."
  @spec change_holiday_calendar(Organisation.t() | HolidayCalendar.t(), map()) ::
          Ecto.Changeset.t()
  def change_holiday_calendar(%Organisation{} = organisation, attrs) do
    HolidayCalendar.changeset(%HolidayCalendar{organisation_id: organisation.id}, attrs)
  end

  def change_holiday_calendar(%HolidayCalendar{} = calendar, attrs) do
    HolidayCalendar.changeset(calendar, attrs)
  end

  @doc "The changeset a public holiday's form binds to."
  @spec change_public_holiday(HolidayCalendar.t() | PublicHoliday.t(), map()) ::
          Ecto.Changeset.t()
  def change_public_holiday(%HolidayCalendar{} = calendar, attrs) do
    PublicHoliday.changeset(%PublicHoliday{holiday_calendar_id: calendar.id}, attrs)
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
  def fetch_organisation(id), do: fetched(Repo.get(Organisation, id))

  @doc "Every holiday calendar the organisation holds, by name."
  @spec holiday_calendars(Ecto.UUID.t()) :: [HolidayCalendar.t()]
  def holiday_calendars(organisation_id) do
    Repo.all(
      from calendar in HolidayCalendar,
        where: calendar.organisation_id == ^organisation_id,
        order_by: calendar.name
    )
  end

  @doc "The holiday calendar, or `:error` where no such calendar exists."
  @spec fetch_holiday_calendar(Ecto.UUID.t()) :: {:ok, HolidayCalendar.t()} | :error
  def fetch_holiday_calendar(id), do: fetched(Repo.get(HolidayCalendar, id))

  @doc "The public holiday, or `:error` where no such holiday exists."
  @spec fetch_public_holiday(Ecto.UUID.t()) :: {:ok, PublicHoliday.t()} | :error
  def fetch_public_holiday(id), do: fetched(Repo.get(PublicHoliday, id))

  @doc "Creates a holiday calendar."
  @spec create_holiday_calendar(Organisation.t(), Person.t() | nil, map()) ::
          Audit.written(HolidayCalendar.t())
  def create_holiday_calendar(organisation, actor, attrs) do
    %HolidayCalendar{organisation_id: organisation.id}
    |> HolidayCalendar.changeset(attrs)
    |> Audit.write("holiday_calendar.created", actor)
  end

  @doc "Amends a holiday calendar."
  @spec update_holiday_calendar(HolidayCalendar.t(), Person.t() | nil, map()) ::
          Audit.written(HolidayCalendar.t())
  def update_holiday_calendar(calendar, actor, attrs) do
    calendar
    |> HolidayCalendar.changeset(attrs)
    |> Audit.write("holiday_calendar.updated", actor)
  end

  @doc "Adds one public holiday to a calendar."
  @spec create_public_holiday(HolidayCalendar.t(), Person.t() | nil, map()) ::
          Audit.written(PublicHoliday.t())
  def create_public_holiday(calendar, actor, attrs) do
    %PublicHoliday{holiday_calendar_id: calendar.id}
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

  @doc "Every public holiday a calendar holds, in date order."
  @spec public_holidays(Ecto.UUID.t()) :: [PublicHoliday.t()]
  def public_holidays(holiday_calendar_id), do: Repo.all(on_calendar(holiday_calendar_id))

  @doc "The public holidays a calendar holds within `range`, in date order."
  @spec public_holidays(Ecto.UUID.t(), Date.Range.t()) :: [PublicHoliday.t()]
  def public_holidays(holiday_calendar_id, range) do
    Repo.all(
      from holiday in on_calendar(holiday_calendar_id),
        where: holiday.date >= ^range.first and holiday.date <= ^range.last
    )
  end

  defp on_calendar(holiday_calendar_id) do
    from holiday in PublicHoliday,
      where: holiday.holiday_calendar_id == ^holiday_calendar_id,
      order_by: holiday.date
  end

  defp fetched(nil), do: :error
  defp fetched(record), do: {:ok, record}
end
