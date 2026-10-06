defmodule Leaf.Ledger.Span do
  @moduledoc """
  A stretch of dates over which one entitlement, one grant period and one work pattern all hold.

  Which dates an entitlement covers a person for is `Leaf.Policies.grant_windows/3`, read from the
  date the organisation started tracking leave; a span is one of those windows cut by the work
  patterns over it, so that everything downstream is handed a stretch of dates, the period it sits
  in and the hours worked over it, and has only to measure them.

  `dates` runs to the end of the entitlement's life and `granting` to the end of its grant window,
  which is the narrower of the two where a policy has stopped offering something people may still
  spend. Grants come from `granting`; a rollover cap falls due at the end of a `period` that
  `dates` covers, since a balance that is still spendable is still subject to its cap.

  Both stop at the date being asked about, so neither says how long the person is there for.
  `employed_to` does, where their employment ends at all, for the one grant that is measured over
  a whole period rather than over the span.
  """

  alias Leaf.Dates
  alias Leaf.Org.Organisation
  alias Leaf.People
  alias Leaf.People.Person
  alias Leaf.People.WorkPattern
  alias Leaf.Policies
  alias Leaf.Policies.PolicyEntitlement

  @type t :: %__MODULE__{
          entitlement: PolicyEntitlement.t(),
          period: Date.Range.t(),
          dates: Date.Range.t(),
          granting: Date.Range.t() | nil,
          employed_to: Date.t() | nil,
          work_pattern: WorkPattern.t()
        }

  @enforce_keys [:entitlement, :period, :dates, :granting, :employed_to, :work_pattern]
  defstruct [:entitlement, :period, :dates, :granting, :employed_to, :work_pattern]

  @doc "Every span up to and including `as_at` over which the person is entitled to something."
  @spec all(Person.t(), Organisation.t(), Date.t()) :: [t()]
  def all(person, organisation, as_at) do
    case tracked_range(person, organisation, as_at) do
      :error -> []
      {:ok, range} -> spans(person, organisation, range)
    end
  end

  @doc """
  The stretch of the person's history a balance as at `as_at` is worked out over.

  Their employment, bounded below by the date the organisation started tracking leave and above by
  the date being asked about. `:error` where those leave nothing.
  """
  @spec tracked_range(Person.t(), Organisation.t(), Date.t()) :: {:ok, Date.Range.t()} | :error
  def tracked_range(person, organisation, as_at) do
    Dates.bounded(
      Enum.max([organisation.tracked_from, person.employment_start_date], Date),
      Dates.earliest(as_at, person.employment_end_date)
    )
  end

  defp spans(person, organisation, range) do
    patterns = People.work_pattern_segments!(person, range)

    for window <- Policies.grant_windows(person, organisation, range),
        {worked, pattern} <- patterns,
        {:ok, dates} <- [Dates.intersect(window.covered, worked.first, worked.last)] do
      %__MODULE__{
        entitlement: window.entitlement,
        period: window.period,
        dates: dates,
        granting: granting(window.granting, dates),
        employed_to: person.employment_end_date,
        work_pattern: pattern
      }
    end
  end

  defp granting(nil, _dates), do: nil

  defp granting(window, dates) do
    case Dates.intersect(window, dates.first, dates.last) do
      :error -> nil
      {:ok, granting} -> granting
    end
  end
end
