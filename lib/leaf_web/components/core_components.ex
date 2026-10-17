defmodule LeafWeb.CoreComponents do
  @moduledoc """
  Core UI components: flashes and form inputs, with an error translation helper.

  The markup here is deliberately unstyled — no classes. Presentation comes from the
  semantic design system in the stylesheet, which selects on the elements themselves.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.set_attribute({"hidden", ""})}
      role="alert"
      data-kind={@kind}
      {@rest}
    >
      <p :if={@title}>{@title}</p>
      <p>{msg}</p>
      <button type="button">Close</button>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []

  attr :help, :string,
    default: nil,
    doc: "shown while the icon by the label is hovered or pressed"

  attr :unit, :string, default: nil, doc: "what the value counts, shown after the box"
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Form.normalize_value("checkbox", assigns[:value]) end)

    ~H"""
    <div>
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span>
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            {described(@id, @errors, @help)}
            {@rest}
          />{@label}<.info :if={@help} />
        </span>
      </label>
      <p :if={@help} id={help_id(@id)} role="tooltip">{@help}</p>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label for={@id}>
        <span :if={@label}>{@label}<.info :if={@help} /></span>
        <select id={@id} name={@name} multiple={@multiple} {described(@id, @errors, @help)} {@rest}>
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
      </label>
      <p :if={@help} id={help_id(@id)} role="tooltip">{@help}</p>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label for={@id}>
        <span :if={@label}>{@label}<.info :if={@help} /></span>
        <textarea id={@id} name={@name} {described(@id, @errors, @help)} {@rest}>{Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <p :if={@help} id={help_id(@id)} role="tooltip">{@help}</p>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <label for={@id}>
        <span :if={@label}>{@label}<.info :if={@help} /></span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          {described(@id, @errors, @help)}
          {@rest}
        />
        <span :if={@unit}>{@unit}</span>
      </label>
      <p :if={@help} id={help_id(@id)} role="tooltip">{@help}</p>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders a choice of one option, each carrying what applies only once it is chosen.

  An option's inner block is rendered beside it while it is the one chosen.

  ```heex
  <.radios field={@form[:expiry_rule]} label="Rollover">
    <:option value="never" label="Rolls over indefinitely" />
    <:option value="cap" label="Rolls over up to a cap of">
      <.input field={@form[:rollover_cap]} aria-label="Rollover cap" unit="days" />
    </:option>
  </.radios>
  ```
  """
  attr :field, FormField, required: true
  attr :label, :string, required: true
  attr :value, :any, doc: "the option chosen, where it is not the field's own value"

  attr :help, :string,
    default: nil,
    doc: "shown while the icon by the label is hovered or pressed"

  slot :option, required: true do
    attr :value, :string, required: true
    attr :label, :string, required: true
  end

  def radios(assigns) do
    assigns =
      assigns
      |> assign(:errors, Enum.map(assigns.field.errors, &translate_error(&1)))
      |> assign(:chosen, to_string(Map.get(assigns, :value, assigns.field.value)))

    ~H"""
    <fieldset>
      <legend>{@label}<.info :if={@help} /></legend>
      <p :if={@help} id={help_id(@field.id)} role="tooltip">{@help}</p>
      <div :for={option <- @option}>
        <label>
          <input
            type="radio"
            name={@field.name}
            value={option.value}
            checked={option.value == @chosen}
            {described(@field.id, @errors, @help)}
          />
          {option.label}
        </label>
        {if option.value == @chosen and option.inner_block, do: render_slot(option)}
      </div>
      <.errors id={@field.id} errors={@errors} />
    </fieldset>
    """
  end

  defp errors(assigns) do
    ~H"""
    <p :for={{msg, n} <- Enum.with_index(@errors, 1)} id={error_id(@id, n)}>{msg}</p>
    """
  end

  defp info(assigns) do
    ~H"""
    <button
      type="button"
      aria-label="Help"
      aria-expanded="false"
      phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"})}
      phx-click-away={JS.set_attribute({"aria-expanded", "false"})}
    >
      <svg
        width="16"
        height="16"
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        aria-hidden="true"
      >
        <circle cx="8" cy="8" r="6.5" /><path d="M8 7.25v4M8 4.75v.01" />
      </svg>
    </button>
    """
  end

  defp described(id, errors, help) do
    ids = [help && help_id(id) | Enum.map(1..length(errors)//1, &error_id(id, &1))]
    by = ids |> Enum.reject(&is_nil/1) |> Enum.join(" ")

    ["aria-invalid": errors != [] && "true", "aria-describedby": by != "" && by]
  end

  defp help_id(id), do: "#{id}-help"

  defp error_id(id, n), do: "#{id}-error-#{n}"

  @doc """
  Translates a changeset error into a message, interpolating its options.
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
