defmodule LeafWeb.AuthorizedEventsTest do
  use ExUnit.Case, async: true

  # A LiveView that names no role for an event is the hole item 2 came out of, so the compiler is
  # what closes it: these are the four ways of getting it wrong, and none of them build.
  defp compile(body) do
    fn ->
      Code.compile_string("""
      defmodule LeafWeb.SpecimenLive#{System.unique_integer([:positive])} do
        use LeafWeb, :live_view

        #{body}

        def render(assigns), do: ~H""
      end
      """)
    end
  end

  test "an event with no role does not compile" do
    assert_raise CompileError,
                 ~r/the "go" event .* has no @role above it/,
                 compile("""
                 def handle_event("go", _params, socket), do: {:noreply, socket}
                 """)
  end

  test "an event asking for something that is not a role does not compile" do
    assert_raise CompileError,
                 ~r/asks for :owner, which is not one of/,
                 compile("""
                 @role :owner
                 def handle_event("go", _params, socket), do: {:noreply, socket}
                 """)
  end

  test "an event given two roles does not compile" do
    assert_raise CompileError,
                 ~r/has more than one @role above it/,
                 compile("""
                 @role :admin
                 @role :member
                 def handle_event("go", _params, socket), do: {:noreply, socket}
                 """)
  end

  test "a further clause of an event stating its own role does not compile" do
    assert_raise CompileError,
                 ~r/is given a @role twice over/,
                 compile("""
                 @role :admin
                 def handle_event("go", %{"now" => _now}, socket), do: {:noreply, socket}
                 @role :member
                 def handle_event("go", _params, socket), do: {:noreply, socket}
                 """)
  end

  test "a further clause of an event carries the role already stated" do
    [{module, _binary} | _rest] =
      compile("""
      @role :admin
      def handle_event("go", %{"now" => _now}, socket), do: {:noreply, socket}
      def handle_event("go", _params, socket), do: {:noreply, socket}
      """).()

    assert module.role_for_event() == %{"go" => :admin}
  end
end
