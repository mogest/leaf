defmodule LeafWeb.DesignSystemTest do
  @moduledoc """
  Holds the design system to being a system.

  The stylesheet selects elements, so a class only appears where the element cannot say which one
  it is. Both directions of that bargain are checked here: markup may not invent a name the
  stylesheet has never heard of, and the stylesheet may not keep a name nothing uses. Either one
  drifting is how a design system turns into a pile of one-off rules. Page scopes are the one
  exception: `main.your-leave` comes from the layout rather than from any markup, so it is exempt.
  """

  use ExUnit.Case, async: true

  @stylesheets Path.wildcard("assets/css/*.css")
  @markup Path.wildcard("lib/leaf_web/**/*.{ex,heex}")

  # A class attribute is either a literal or an expression; a name inside the expression is still
  # quoted, so both forms give up their names to the same pass over the quoted strings.
  @attribute ~r/\bclass=(?:"[^"]*"|\{[^}]*\})/
  @quoted ~r/"([^"]*)"/

  # A class selector, told from a decimal by the digit that would precede it. Comments, strings and
  # urls go first, so a filename inside one cannot read as a selector. A page scope — `main.x`,
  # written from `Layouts.app`'s `page` — is not a class anyone spells out, so it is passed over.
  @selector ~r/(?<!\d)(?<!main)\.([a-z][a-z0-9-]*)/
  @not_selectors ~r|/\*.*?\*/|s
  @literal ~r/"[^"]*"|'[^']*'|url\([^)]*\)/

  test "every class the markup uses is defined in the stylesheet" do
    assert Enum.sort(MapSet.difference(used(), defined())) == []
  end

  test "every class the stylesheet defines is used by the markup" do
    assert Enum.sort(MapSet.difference(defined(), used())) == []
  end

  defp used do
    @markup
    |> Enum.flat_map(&names(@attribute, File.read!(&1)))
    |> Enum.flat_map(&names(@quoted, &1))
    |> Enum.flat_map(&String.split/1)
    |> MapSet.new()
  end

  defp defined do
    @stylesheets
    |> Enum.flat_map(&names(@selector, selectors_only(File.read!(&1))))
    |> MapSet.new()
  end

  defp selectors_only(stylesheet) do
    stylesheet |> String.replace(@not_selectors, " ") |> String.replace(@literal, " ")
  end

  defp names(regex, source) do
    regex |> Regex.scan(source) |> Enum.map(&List.last/1)
  end
end
