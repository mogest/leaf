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

  @rail [
    {"At a glance", "/", ~w(at-a-glance request-leave)},
    {"Balances", "/balances", ~w(balances)},
    {"Your requests", "/leave", ~w(your-requests)},
    @approvals,
    {"Who's away", "/away", ~w(who-is-away)}
  ]

  @administered [
    {"People", "/people", ~w(people)},
    {"Settings", "/settings", ~w(settings)}
  ]

  @doc """
  Renders the frame every page sits in: the rail down the side, the page beside it.

  `page` names the page, and becomes the class the page's own rules are scoped under.

  ## Examples

      <Layouts.app flash={@flash} page="at-a-glance">
        <h1>At a glance</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :page, :string, required: true, doc: "which page this is, in kebab case"

  attr :viewer, :map,
    default: nil,
    doc: "the `LeafWeb.Viewer` for whoever is signed in, or nil while nobody is"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <nav>
      <a href="/">
        <svg
          width="19"
          height="19"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M4 20c0-8 5-14 16-16 0 11-6 16-13 16H4z" />
          <path d="M4.5 19.5C8 16 12 13 17 11" />
        </svg>
        <span>Leaf</span>
      </a>
      <ul>
        <li :for={{label, path, pages} <- rail(@viewer)}>
          <a href={path} aria-current={current(@page, pages)}>{label}</a>
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
    </nav>
    <main class={@page}>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  defp rail(%Viewer{admin?: true}), do: @rail ++ @administered
  defp rail(%Viewer{approver?: true}), do: @rail
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
