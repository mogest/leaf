defmodule LeafWeb.Wording do
  @moduledoc """
  How the pages say things.

  Every page works its strings out before rendering them, so that no markup decides anything. The
  ones more than one page says are here, and the rules they follow are the ones the design settled:
  units in full, no trailing zeros, plain words over mechanism, and nothing at all where there is
  nothing to say.
  """

  alias Leaf.Leave.Day
  alias Leaf.Leave.Request
  alias Leaf.Ledger.Lot
  alias Leaf.Ledger.Statement
  alias Leaf.People.Person
  alias Leaf.Policies.LeaveType

  @typedoc "A request as a page shows it."
  @type filed :: %{
          id: Ecto.UUID.t(),
          dates: String.t(),
          type: String.t(),
          amount: String.t(),
          standing: atom(),
          label: String.t(),
          progress: String.t()
        }

  @doc """
  A request said in five parts: when it is, what it draws on, what it comes to, where it got to,
  and how it got there.

  It is read a row at a time against others, so the dates are the short form, and how it got there
  leaves out the word its standing already says.

  `awaiting` is who a pending one is with, and is left out where a page is not saying.
  """
  @spec filed(Request.t(), Date.t(), String.t() | nil) :: filed()
  def filed(request, today, awaiting \\ nil) do
    standing = standing(request, today)

    %{
      id: request.id,
      dates: brief_dates(request),
      type: types(request),
      amount: amount(request),
      standing: standing,
      label: standing |> Atom.to_string() |> String.capitalize(),
      progress: progress(request, awaiting)
    }
  end

  @typedoc "A balance as a page shows it."
  @type held :: %{
          name: String.t(),
          amount: String.t(),
          unit: String.t(),
          awaiting: String.t() | nil,
          expiry: String.t() | nil
        }

  @doc """
  What somebody holds in one leave type: the figure, what is waiting on an answer, and what is
  about to lapse.

  `awaiting` is `Leaf.Ledger.awaiting/1`, keyed by leave type. Nothing waiting and nothing lapsing
  each say nothing at all.
  """
  @spec held(Statement.t(), %{Ecto.UUID.t() => Decimal.t()}) :: held()
  def held(statement, awaiting) do
    %{
      name: statement.leave_type.name,
      amount: number(statement.balance),
      unit: unit(statement.balance, statement.leave_type.unit),
      awaiting: asked(awaiting[statement.leave_type.id], statement.leave_type.unit),
      expiry: expiry(statement)
    }
  end

  @doc "The span a request's days cover, as one date or as two."
  @spec dates(Request.t()) :: String.t()
  def dates(request) do
    {first, last} = covered(request)

    span(first, last)
  end

  @doc "The span a request's days cover, short enough for a column of them: Mon 2 – Fri 6 Mar."
  @spec brief_dates(Request.t()) :: String.t()
  def brief_dates(request) do
    {first, last} = covered(request)

    brief_span(first, last)
  end

  @doc """
  What a request comes to.

  It can be asked for in both units at once, and each is only worth what it says it is: what a day
  off comes to in hours follows from the date, not from the request.
  """
  @spec amount(Request.t()) :: String.t()
  def amount(request) do
    request.days
    |> Enum.group_by(& &1.unit, & &1.amount)
    |> Enum.map_join(" and ", fn {unit, amounts} -> figure(total(amounts), unit) end)
  end

  @doc "The leave types a request draws on, named."
  @spec types(Request.t()) :: String.t()
  def types(request) do
    [first | rest] = request.days |> Enum.map(& &1.leave_type.name) |> Enum.uniq()

    joined([first | Enum.map(rest, &String.downcase/1)])
  end

  @doc "A stretch of dates, as one date or as two: Monday 2 – Friday 6 March."
  @spec span(Date.t(), Date.t()) :: String.t()
  def span(date, date), do: weekday(date)
  def span(first, last), do: stretch(first, last, "%A %-d", &weekday/1)

  @doc "A date with the day of the week it falls on: Saturday 22 August."
  @spec weekday(Date.t()) :: String.t()
  def weekday(date), do: Calendar.strftime(date, "%A %-d %B")

  @doc "A date short enough for a column of them: Sat 22 Aug."
  @spec brief(Date.t()) :: String.t()
  def brief(date), do: Calendar.strftime(date, "%a %-d %b")

  @doc "A date in full: 22 August 2026."
  @spec date(Date.t() | nil) :: String.t() | nil
  def date(nil), do: nil
  def date(date), do: Calendar.strftime(date, "%-d %B %Y")

  @doc "A date narrow enough for a column of them, the year kept: 22 Aug 2026."
  @spec brief_date(Date.t() | DateTime.t() | nil) :: String.t() | nil
  def brief_date(nil), do: nil
  def brief_date(at), do: Calendar.strftime(at, "%-d %b %Y")

  @doc "A date within the year it is being read in: 18 August."
  @spec day_and_month(Date.t() | DateTime.t()) :: String.t()
  def day_and_month(at), do: Calendar.strftime(at, "%-d %B")

  @doc "A month, named with its year only where that is not the year being read in: August 2030."
  @spec month(Date.t(), Date.t()) :: String.t()
  def month(%{year: year} = date, %{year: year}), do: Calendar.strftime(date, "%B")
  def month(date, _today), do: Calendar.strftime(date, "%B %Y")

  @doc "A moment, to the minute: 22 August 2026, 14:32."
  @spec moment(DateTime.t()) :: String.t()
  def moment(at), do: Calendar.strftime(at, "%-d %B %Y, %H:%M")

  @doc "An amount with its unit in full: 9 hours, 1 day."
  @spec figure(Decimal.t(), Day.unit()) :: String.t()
  def figure(amount, unit), do: "#{number(amount)} #{unit(amount, unit)}"

  @doc "A figure rounded where it is shown and nowhere before it, with nothing trailing: 33."
  @spec number(Decimal.t()) :: String.t()
  def number(amount) do
    amount |> Decimal.round(2) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  @doc "A unit named for the amount it counts."
  @spec unit(Decimal.t(), Day.unit()) :: String.t()
  def unit(amount, unit), do: named(unit, Decimal.equal?(Decimal.abs(amount), 1))

  @doc "The name a leave type is chosen by, and what it counts in."
  @spec leave_type(LeaveType.t()) :: String.t()
  def leave_type(leave_type), do: "#{leave_type.name} (in #{leave_type.unit})"

  @doc "Somebody's initials, for standing in for their face."
  @spec initials(String.t()) :: String.t()
  def initials(name) do
    name |> String.split(~r/\s+/, trim: true) |> Enum.map_join(&String.first/1)
  end

  @doc "Whoever acted, or the system where nobody did."
  @spec actor(Person.t() | nil) :: String.t()
  def actor(nil), do: "the system"
  def actor(person), do: person.name

  defp asked(nil, _unit), do: nil
  defp asked(amount, unit), do: "#{figure(amount, unit)} awaiting approval"

  # What is going to happen to the balance, and nothing at all where nothing is. The soonest lot
  # to lapse is the one worth saying; one that is the whole balance says so without the figure.
  defp expiry(statement) do
    case statement.lots |> Lot.soonest_first() |> List.first() do
      %{expires_on: nil} -> nil
      nil -> nil
      lot -> lapsing(lot, statement)
    end
  end

  defp lapsing(lot, statement) do
    date = day_and_month(lot.expires_on)

    case Decimal.equal?(lot.amount, statement.balance) do
      true -> "Expires #{date}"
      false -> "#{figure(lot.amount, statement.leave_type.unit)} #{expire(lot.amount)} on #{date}"
    end
  end

  defp expire(amount) do
    case Decimal.equal?(amount, 1) do
      true -> "expires"
      false -> "expire"
    end
  end

  defp brief_span(date, date), do: brief(date)
  defp brief_span(first, last), do: stretch(first, last, "%a %-d", &brief/1)

  # Where both ends fall in the same month, the month is said once, at the end.
  defp stretch(first, last, day, write) do
    case {first.year, first.month} == {last.year, last.month} do
      true -> "#{Calendar.strftime(first, day)} – #{write.(last)}"
      false -> "#{write.(first)} – #{write.(last)}"
    end
  end

  defp covered(request) do
    dates = Enum.map(request.days, & &1.date)

    {Enum.min(dates, Date), Enum.max(dates, Date)}
  end

  # Names run together as a sentence would run them.
  defp joined([name]), do: name

  defp joined(names) do
    {leading, [last]} = Enum.split(names, -1)

    "#{Enum.join(leading, ", ")} and #{last}"
  end

  defp named(:hours, true), do: "hour"
  defp named(:hours, false), do: "hours"
  defp named(:days, true), do: "day"
  defp named(:days, false), do: "days"

  defp total(amounts), do: Enum.reduce(amounts, &Decimal.add/2)

  # Leave that has already happened is a different thing to read from leave still to come.
  defp standing(%{status: :approved} = request, today), do: taken(last(request), today)
  defp standing(request, _today), do: request.status

  defp taken(last, today) do
    case Date.before?(last, today) do
      true -> :taken
      false -> :approved
    end
  end

  defp last(request), do: request.days |> Enum.map(& &1.date) |> Enum.max(Date)

  # Whoever it is with or whoever settled it, and when. What they did is the standing's to say.
  defp progress(%{status: :pending} = request, nil),
    do: "sent #{brief_date(request.inserted_at)}"

  defp progress(%{status: :pending} = request, awaiting) do
    "with #{awaiting} since #{brief_date(request.inserted_at)}"
  end

  defp progress(%{status: :declined, review_comment: comment} = request, _awaiting)
       when is_binary(comment) do
    "#{request.reviewed_by.name} said #{comment}"
  end

  defp progress(request, _awaiting) do
    "#{request.reviewed_by.name} · #{brief_date(request.reviewed_at)}"
  end
end
