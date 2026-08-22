defmodule LeafWeb.Layouts do
  @moduledoc """
  Layouts and their related components.
  """
  use LeafWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the frame every page sits in: the rail down the side, the page beside it.

  `page` names the page, and becomes the class the page's own rules are scoped under.

  ## Examples

      <Layouts.app flash={@flash} page="your-leave">
        <h1>Your leave</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :page, :string, required: true, doc: "which page this is, in kebab case"

  attr :current_person, :map,
    default: nil,
    doc: "whoever is signed in, or nil while nobody is"

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
        <li><a href="/" aria-current={current(@page, "your-leave")}>Your leave</a></li>
        <li><a href="#" aria-current={current(@page, "your-calendar")}>Your calendar</a></li>
        <li><a href="#" aria-current={current(@page, "who-is-away")}>Who is away</a></li>
        <li><a href="#" aria-current={current(@page, "people")}>People</a></li>
      </ul>
      <p :if={@current_person}>
        <b>{initials(@current_person.name)}</b>
        <span>{@current_person.name}</span>
      </p>
    </nav>
    <main class={@page}>
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  defp current(page, page), do: "page"
  defp current(_page, _other), do: nil

  defp initials(name) do
    name |> String.split(~r/\s+/, trim: true) |> Enum.map_join(&String.first/1)
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
