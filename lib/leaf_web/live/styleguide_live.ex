defmodule LeafWeb.StyleguideLive do
  @moduledoc """
  Every part the pages are built from, on one page, in development only.

  A part that is not here does not exist. The specimen is deliberately static: it is where the
  system is judged, so nothing on it should depend on there being data.
  """

  use LeafWeb, :live_view

  alias Leaf.Leave.Month
  alias Leaf.People.Person
  alias LeafWeb.Viewer

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

  @requests [
    %{
      id: "pending",
      dates: "Friday 25 September",
      amount: "9 hours",
      standing: :pending,
      label: "Pending",
      detail: "Quarterly leave and annual leave · sent to Ari Kelburn on 18 August"
    },
    %{
      id: "approved",
      dates: "Monday 5 – Friday 9 October",
      amount: "36 hours",
      standing: :approved,
      label: "Approved",
      detail: "Annual leave · approved by Ari Kelburn on 2 August"
    },
    %{
      id: "declined",
      dates: "Monday 2 November",
      amount: "9 hours",
      standing: :declined,
      label: "Declined",
      detail: "Annual leave · Ari Kelburn said three of you are already away that week"
    }
  ]

  @august ~D[2026-08-01]
  @today ~D[2026-08-22]

  # Standing enough to be shown every entry the rail has.
  @viewer %Viewer{person: %Person{name: "Rae Halloran"}, admin?: true, approver?: true}

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
     |> assign(:requests, @requests)
     |> assign(:units, [{"hours", "hours"}, {"days", "days"}])
     |> assign(:form, to_form(%{}, as: :specimen))
     |> assign(:months, [month()])
     |> assign(:today, @today)
     |> assign(:here, @here)
     |> assign(:viewer, @viewer)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} page="styleguide" viewer={@viewer}>
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
            <h1>At a glance</h1>
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
          <h2>Moving between settings</h2>
        </header>
        <Parts.settings_nav here="leave-types" />
      </section>

      <section>
        <header>
          <h2>A form</h2>
        </header>
        <.form id="specimen" for={@form}>
          <section>
            <header>
              <h2>What it is</h2>
              <p>anything quiet the heading wants to say</p>
            </header>
            <.input name="specimen[name]" value="Quarterly leave" label="Name" />
            <.input
              name="specimen[unit]"
              type="select"
              value="hours"
              label="Counted in"
              options={@units}
            />
            <.input
              name="specimen[amount]"
              value="eight"
              label="Amount per day"
              errors={["has to be a number"]}
            />
            <.input name="specimen[note]" type="textarea" value="" label="Note" />
            <.input
              name="specimen[pro_rated]"
              type="checkbox"
              checked
              label="Pro-rated by the hours they work"
            />
          </section>
          <footer>
            <button class="button" type="button">Save</button>
            <a href={@here}>Cancel</a>
          </footer>
        </.form>
      </section>

      <section>
        <header>
          <h2>A table</h2>
        </header>
        <table>
          <thead>
            <tr>
              <th scope="col">Name</th>
              <th scope="col">Counted in</th>
              <th scope="col">Standing</th>
              <th scope="col"></th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row">Annual leave</th>
              <td>hours</td>
              <td>offered</td>
              <td><button type="button">Withdraw</button></td>
            </tr>
            <tr data-tone="past">
              <th scope="row">Quarterly leave</th>
              <td>hours</td>
              <td>withdrawn 1 January 2026</td>
              <td><button type="button">Offer again</button></td>
            </tr>
          </tbody>
        </table>
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
        <Parts.requests requests={@requests}>
          <:empty>You have not asked for any leave yet.</:empty>
          <:footer>Showing your three most recent. <a href={@here}>See all 23</a>.</:footer>
        </Parts.requests>
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
