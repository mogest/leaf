defmodule LeafWeb.StyleguideLive do
  @moduledoc """
  Every part the pages are built from, on one page, in development only.

  A part that is not here does not exist. The specimen is deliberately static: it is where the
  system is judged, so nothing on it should depend on there being data.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave.Month

  @swatches [
    {"Ground", "--ground", "Behind the rail"},
    {"Sheet", "--sheet", "What a page sits on"},
    {"Panel", "--panel", "A block set apart"},
    {"Ink", "--ink", "Reading text"},
    {"Ink soft", "--ink-soft", "Anything secondary"},
    {"Green", "--green", "Leave you have, and the one action"},
    {"Clay", "--clay", "Leave spent, and refusals"},
    {"Ochre", "--ochre", "Time running out"}
  ]

  @standings [
    {"Pending", "pending"},
    {"Approved", "approved"},
    {"Declined", "declined"},
    {"Taken", "taken"},
    {"Cancelled", "cancelled"}
  ]

  @august ~D[2026-08-01]
  @today ~D[2026-08-22]

  # Where a part that steps through something steps to: nowhere but here. The route is only in
  # development, so it is not one verified routes can be asked about.
  @here "/dev/styleguide"

  # A month is enough to show every state a day can be in.
  @weeks [
    [nil, nil, nil, nil, nil, {1, :off}, {2, :off}],
    [{3, :work}, {4, :work}, {5, :work}, {6, :off}, {7, :work}, {8, :off}, {9, :off}],
    [
      {10, :approved},
      {11, :approved},
      {12, :approved},
      {13, :off},
      {14, :pending},
      {15, :off},
      {16, :off}
    ],
    [{17, :work}, {18, :work}, {19, :work}, {20, :off}, {21, :work}, {22, :today}, {23, :off}],
    [{24, :work}, {25, :work}, {26, :holiday}, {27, :off}, {28, :work}, {29, :off}, {30, :off}],
    [{31, :work}, nil, nil, nil, nil, nil, nil]
  ]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Specimen sheet")
     |> assign(:swatches, @swatches)
     |> assign(:standings, @standings)
     |> assign(:months, [month()])
     |> assign(:today, @today)
     |> assign(:here, @here)
     |> assign(:person, %{name: "Rae Halloran"})}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="styleguide" current_person={@person}>
      <header>
        <h1>Specimen sheet</h1>
        <a class="button" href="/">Back to the app</a>
      </header>

      <section>
        <header>
          <h2>Palette</h2>
        </header>
        <ul>
          <li :for={{name, token, use_for} <- @swatches} style={"--swatch: var(#{token})"}>
            <span>{name}</span>
            <small>{use_for}</small>
          </li>
        </ul>
      </section>

      <section>
        <header>
          <h2>Type</h2>
        </header>
        <dl>
          <dt>
            <h1>Your leave</h1>
          </dt>
          <dd>Newsreader 400, page title</dd>
          <dt>
            <h2>Balances</h2>
          </dt>
          <dd>Figtree 600, a section</dd>
          <dt>Leave dated while the entitlement was still offered can still be filed.</dt>
          <dd>Figtree 400, reading text</dd>
          <dt><small>Recorded only, no balance</small></dt>
          <dd>Figtree 400, anything secondary</dd>
        </dl>
      </section>

      <section>
        <header>
          <h2>Actions and standing</h2>
        </header>
        <div>
          <a class="button" href="#">Request leave</a>
          <a href="#">A plain link</a>
          <span :for={{label, standing} <- @standings} class="standing" data-standing={standing}>
            {label}
          </span>
        </div>
      </section>

      <section>
        <header>
          <h2>Calendar</h2>
        </header>
        <Parts.calendar months={@months} today={@today} earlier={@here} later={@here} />
      </section>

      <section>
        <header>
          <h2>Balances</h2>
        </header>
        <section class="balances">
          <header>
            <h2>Balances</h2>
            <p>as at today</p>
          </header>
          <dl>
            <dt>Annual leave</dt>
            <dd>267.78 <small>hours</small></dd>
            <dt>Sick leave</dt>
            <dd>33 <small>days</small></dd>
            <dd>13 days expire on 14 December</dd>
            <dt>Birthday leave</dt>
            <dd>1 <small>day</small></dd>
            <dd>Expires Monday 24 August</dd>
          </dl>
        </section>
      </section>

      <section>
        <header>
          <h2>Requests</h2>
        </header>
        <section class="requests">
          <header>
            <h2>Requests</h2>
          </header>
          <ol>
            <li>
              <p>
                <span>Friday 25 September</span>
                <span>9 hours</span>
                <span class="standing" data-standing="pending">Pending</span>
              </p>
              <p>Quarterly leave and annual leave · sent to Ari Kelburn on 18 August</p>
            </li>
            <li>
              <p>
                <span>Monday 5 – Friday 9 October</span>
                <span>36 hours</span>
                <span class="standing" data-standing="approved">Approved</span>
              </p>
              <p>Annual leave · approved by Ari Kelburn on 2 August</p>
            </li>
            <li>
              <p>
                <span>Monday 2 November</span>
                <span>9 hours</span>
                <span class="standing" data-standing="declined">Declined</span>
              </p>
              <p>Annual leave · Ari Kelburn said three of you are already away that week</p>
            </li>
          </ol>
          <p>Showing your three most recent. <a href="#">See all 23</a>.</p>
        </section>
      </section>
    </Layouts.app>
    """
  end

  # The specimen stands on no data, so its month is written out and then shaped like a real one.
  defp month do
    %Month{starts_on: @august, weeks: Enum.map(@weeks, fn week -> Enum.map(week, &day/1) end)}
  end

  defp day(nil), do: nil

  defp day({number, state}) do
    %{
      date: Date.new!(@august.year, @august.month, number),
      working?: state not in [:off, :today],
      leave: leave(state),
      holiday: holiday(state)
    }
  end

  defp leave(state) when state in [:approved, :pending], do: state
  defp leave(_state), do: nil

  defp holiday(:holiday), do: "Labour Day"
  defp holiday(_state), do: nil
end
