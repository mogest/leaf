defmodule Leaf.Org do
  @moduledoc "The organisation, its working-week conventions, and its public holiday calendars."

  import Ecto.Query

  alias Leaf.Org.HolidayCalendar
  alias Leaf.Org.Organisation
  alias Leaf.Org.PublicHoliday
  alias Leaf.Repo

  @doc "Creates an organisation."
  @spec create_organisation(map()) :: {:ok, Organisation.t()} | {:error, Ecto.Changeset.t()}
  def create_organisation(attrs) do
    %Organisation{} |> Organisation.changeset(attrs) |> Repo.insert()
  end

  @doc "Every organisation, oldest first."
  @spec organisations() :: [Organisation.t()]
  def organisations, do: Repo.all(from o in Organisation, order_by: o.inserted_at)

  @doc "The organisation, or `:error` where no such organisation exists."
  @spec fetch_organisation(Ecto.UUID.t()) :: {:ok, Organisation.t()} | :error
  def fetch_organisation(id) do
    case Repo.get(Organisation, id) do
      nil -> :error
      organisation -> {:ok, organisation}
    end
  end

  @doc "Creates a holiday calendar."
  @spec create_holiday_calendar(map()) ::
          {:ok, HolidayCalendar.t()} | {:error, Ecto.Changeset.t()}
  def create_holiday_calendar(attrs) do
    %HolidayCalendar{} |> HolidayCalendar.changeset(attrs) |> Repo.insert()
  end

  @doc "Adds one public holiday to a calendar."
  @spec create_public_holiday(map()) :: {:ok, PublicHoliday.t()} | {:error, Ecto.Changeset.t()}
  def create_public_holiday(attrs) do
    %PublicHoliday{} |> PublicHoliday.changeset(attrs) |> Repo.insert()
  end

  @doc "The public holidays a calendar holds within `range`, in date order."
  @spec public_holidays(Ecto.UUID.t(), Date.Range.t()) :: [PublicHoliday.t()]
  def public_holidays(holiday_calendar_id, range) do
    Repo.all(
      from holiday in PublicHoliday,
        where: holiday.holiday_calendar_id == ^holiday_calendar_id,
        where: holiday.date >= ^range.first and holiday.date <= ^range.last,
        order_by: holiday.date
    )
  end
end
