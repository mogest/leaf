defmodule LeafWeb.AuthorizedEvents do
  @moduledoc """
  Says which role each of a LiveView's events asks for, and turns anybody else away.

  Every `handle_event` carries a `@role` above it — `:member` for one anybody signed in may fire,
  `:admin` for one only an administrator may — and a handler without one does not compile. A page a
  member opens can still carry an administrator's buttons, so hiding a button is not what stops it
  being clicked; saying which role an event asks for is not optional, so no event can be left open
  by having been forgotten.

  The check runs before the event reaches the view, attached by `LeafWeb.SignIn`'s `:current_person`
  hook, which every live session runs.
  """

  alias Phoenix.LiveView

  @roles [:admin, :member]

  @doc false
  defmacro __using__(_opts) do
    quote do
      Module.put_attribute(__MODULE__, :role_for_event, %{})
      Module.register_attribute(__MODULE__, :role, accumulate: true)

      @on_definition unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc "Puts the check in front of every event the socket's view handles."
  @spec enforce(LiveView.Socket.t()) :: LiveView.Socket.t()
  def enforce(socket) do
    LiveView.attach_hook(socket, :authorized_events, :handle_event, &asked_for/3)
  end

  @doc false
  def __on_definition__(env, _kind, :handle_event, [event | _rest], _guards, _body) do
    declared(env, event, Module.get_attribute(env.module, :role), stated(env.module))
  end

  def __on_definition__(env, _kind, _name, _args, _guards, _body) do
    Module.delete_attribute(env.module, :role)
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def role_for_event, do: @role_for_event
    end
  end

  defp asked_for(event, _params, socket) do
    case holds?(socket.assigns.current_person, socket.view.role_for_event()[event]) do
      true -> {:cont, socket}
      false -> {:halt, LiveView.put_flash(socket, :error, "That is not yours to do.")}
    end
  end

  defp holds?(nil, _role), do: false
  defp holds?(%{role: :admin}, _role), do: true
  defp holds?(_person, :admin), do: false
  defp holds?(_person, _role), do: true

  # A further clause of an event already declared brings no attribute of its own.
  defp declared(env, event, [], stated) do
    case Map.has_key?(stated, event) do
      true -> :ok
      false -> refuse(env, event, "has no @role above it")
    end
  end

  defp declared(env, event, [role], stated) when role in @roles do
    case Map.has_key?(stated, event) do
      true -> refuse(env, event, "is given a @role twice over")
      false -> state(env.module, stated, event, role)
    end
  end

  defp declared(env, event, [role], _stated) do
    refuse(env, event, "asks for #{inspect(role)}, which is not one of #{inspect(@roles)}")
  end

  defp declared(env, event, _roles, _stated) do
    refuse(env, event, "has more than one @role above it")
  end

  defp state(module, stated, event, role) do
    Module.delete_attribute(module, :role)
    Module.put_attribute(module, :role_for_event, Map.put(stated, event, role))
  end

  defp stated(module), do: Module.get_attribute(module, :role_for_event, %{})

  defp refuse(env, event, complaint) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: "the #{inspect(event)} event in #{inspect(env.module)} #{complaint}"
  end
end
