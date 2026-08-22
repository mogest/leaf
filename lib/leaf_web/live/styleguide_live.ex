defmodule LeafWeb.StyleguideLive do
  @moduledoc """
  Every part the pages are built from, on one page, in development only.

  A part that is not here does not exist. The specimen is deliberately static: it is where the
  system is judged, so nothing on it should depend on there being data.
  """

  use LeafWeb, :live_view

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
    {"Pending", nil},
    {"Approved", "approved"},
    {"Declined", "declined"},
    {"Taken", "taken"}
  ]

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
     |> assign(:weeks, @weeks)
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
        <.calendar weeks={@weeks} />
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
                <span class="standing">Pending</span>
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

  attr :weeks, :list, required: true

  defp calendar(assigns) do
    ~H"""
    <section class="calendar">
      <header>
        <h2>Calendar</h2>
      </header>
      <nav>
        <a href="#" aria-label="Earlier months">
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M10 3L5 8l5 5" />
          </svg>
        </a>
        <div>
          <table>
            <caption>August</caption>
            <thead>
              <tr>
                <th :for={{initial, index} <- Enum.with_index(~w(M T W T F S S))} scope="col">
                  <span aria-hidden={index >= 0 && "true"}>{initial}</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={week <- @weeks}>
                <td
                  :for={day <- week}
                  data-working={working(day)}
                  data-leave={leave(day)}
                  data-holiday={day && elem(day, 1) == :holiday}
                  data-today={day && elem(day, 1) == :today}
                  aria-current={day && elem(day, 1) == :today && "date"}
                >
                  {day && elem(day, 0)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <a href="#" aria-label="Later months">
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            stroke="currentColor"
            stroke-width="1.7"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M6 3l5 5-5 5" />
          </svg>
        </a>
      </nav>
      <ul>
        <li data-leave="approved">Approved</li>
        <li data-leave="pending">Waiting</li>
        <li data-holiday>Public holiday</li>
        <li data-today>Today</li>
        <li>Faded days are ones you do not work</li>
      </ul>
    </section>
    """
  end

  defp working({_day, state}) when state in [:off, :today], do: "no"
  defp working(_day), do: nil

  defp leave({_day, :approved}), do: "approved"
  defp leave({_day, :pending}), do: "pending"
  defp leave(_day), do: nil
end
