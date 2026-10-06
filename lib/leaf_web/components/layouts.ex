defmodule LeafWeb.Layouts do
  @moduledoc """
  Layouts and their related components.
  """
  use LeafWeb, :html

  alias LeafWeb.Viewer

  embed_templates "layouts/*"

  # Each entry, where it goes, and the pages that light it up. A page reached from an entry stands
  # under it, so a form opened off "People" leaves the rail where the reader left it.
  @approvals {"Approvals", "/approvals", ~w(approvals)}
  @people {"People", "/people", ~w(people)}

  @rail [
    {"At a glance", "/", ~w(at-a-glance request-leave)},
    {"Your balances", "/balances", ~w(balances)},
    {"Your requests", "/leave", ~w(your-requests)},
    {"Who's away", "/away", ~w(who-is-away)},
    {"Org chart", "/chart", ~w(chart)},
    @approvals
  ]

  @administered [
    @people,
    {"Settings", "/settings", ~w(settings)}
  ]

  @doc """
  Renders the frame every page sits in: the rail down the side, the page beside it.

  `page` names the page, and becomes the class the page's own rules are scoped under. It also
  lights the rail entry the page stands under, unless `rail` names another page to light instead.

  ## Examples

      <Layouts.app flash={@flash} page="at-a-glance">
        <h1>At a glance</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :page, :string, required: true, doc: "which page this is, in kebab case"
  attr :rail, :string, default: nil, doc: "the page whose rail entry to light, where not `page`"

  attr :viewer, :map,
    default: nil,
    doc: "the `LeafWeb.Viewer` for whoever is signed in, or nil while nobody is"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <nav>
      <.link navigate="/">
        <svg viewBox="4 4 40 40" aria-hidden="true">
          <rect x="4" y="4" width="18" height="18" rx="4" />
          <rect x="4" y="26" width="18" height="18" rx="4" />
          <rect x="26" y="26" width="18" height="18" rx="4" />
          <path d="M44 4A18 18 0 0 1 26 22A18 18 0 0 1 44 4Z" fill="currentColor" />
        </svg>
        <span>leaf</span>
      </.link>
      <ul id="pages" popover>
        <li :for={{label, path, pages} <- rail(@viewer)}>
          <.link navigate={path} aria-current={current(@rail || @page, pages)}>{label}</.link>
        </li>
      </ul>
      <div :if={@viewer}>
        <button popovertarget="account" aria-label="Your account">
          <b>{Wording.initials(@viewer.person.name)}</b>
          <span>{@viewer.person.name}</span>
        </button>
        <ul id="account" popover>
          <li>
            <.link href="/sign-out" method="delete">Sign out</.link>
          </li>
        </ul>
      </div>
      <button popovertarget="pages" aria-label="Menu">
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          aria-hidden="true"
        >
          <path d="M4 7h16M4 12h16M4 17h16" />
        </svg>
      </button>
    </nav>
    <main class={@page}>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  defp rail(%Viewer{admin?: true}), do: @rail ++ @administered
  defp rail(%Viewer{approver?: true}), do: @rail ++ [@people]
  defp rail(_viewer), do: @rail -- [@approvals]

  defp current(page, pages) do
    case page in pages do
      true -> "page"
      false -> nil
    end
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
      </.flash>
    </div>
    """
  end
end
