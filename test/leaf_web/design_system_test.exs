defmodule LeafWeb.DesignSystemTest do
  @moduledoc """
  Holds the design system to being a system.

  The stylesheet selects elements, so a class only appears where the element cannot say which one
  it is. Both directions of that bargain are checked here: markup may not invent a name the
  stylesheet has never heard of, and the stylesheet may not keep a name nothing uses. Either one
  drifting is how a design system turns into a pile of one-off rules.

  A page scope — a class on `main` — is a page's name, which `Layouts.app` writes from its `page`
  attribute. Every scope the stylesheet writes has to name a page, and no page may share its name
  with a part, whose rules would otherwise style the page.
  """

  use ExUnit.Case, async: true

  @stylesheets Path.wildcard("assets/css/*.css")
  @markup Path.wildcard("lib/leaf_web/**/*.{ex,heex}")
  @code Path.wildcard("lib/**/*.{ex,heex}")

  # A class attribute is either a literal or an expression; a name inside the expression is still
  # quoted, so both forms give up their names to the same pass over the quoted strings.
  @attribute ~r/\bclass=(?:"[^"]*"|(\{(?:[^{}]|(?1))*\}))/
  @quoted ~r/"([^"]*)"/
  @page ~r/<main[^>]*\bclass="([^"]*)"|\bpage="([^"]*)"/

  # A class selector, told from a decimal by the digit that would precede it. Comments, strings and
  # urls go first, so a filename inside one cannot read as a selector.
  @selector ~r/(?<!\d)(?<!main)\.([a-z][a-z0-9-]*)/
  @page_scope ~r/\bmain\.([a-z][a-z0-9-]*)/
  @data_value ~r/\[data-[a-z-]+="([^"]*)"\]/
  @not_selectors ~r|/\*.*?\*/|s
  @literal ~r/"[^"]*"|'[^']*'|url\([^)]*\)/

  test "every class the markup uses is defined in the stylesheet" do
    assert Enum.sort(MapSet.difference(used(), defined())) == []
  end

  test "every class the stylesheet defines is used by the markup" do
    assert Enum.sort(MapSet.difference(defined(), used())) == []
  end

  test "every page scope the stylesheet writes names a page" do
    assert Enum.sort(MapSet.difference(stylesheet_names(@page_scope), pages())) == []
  end

  test "no page shares its name with a part" do
    assert Enum.sort(MapSet.intersection(pages(), defined())) == []
  end

  test "every data value the stylesheet selects is one the code can write" do
    code = Enum.map_join(@code, &File.read!/1)

    unwritten =
      @stylesheets
      |> Enum.flat_map(&names(@data_value, String.replace(File.read!(&1), @not_selectors, " ")))
      |> Enum.reject(&Regex.match?(~r/"#{Regex.escape(&1)}"|:#{Regex.escape(&1)}\b/, code))

    assert Enum.uniq(unwritten) == []
  end

  defp used do
    MapSet.difference(classes(), pages())
  end

  defp classes do
    @markup
    |> Enum.flat_map(&names(@attribute, File.read!(&1)))
    |> Enum.flat_map(&names(@quoted, &1))
    |> Enum.flat_map(&String.split/1)
    |> MapSet.new()
  end

  defp pages do
    @markup
    |> Enum.flat_map(&names(@page, File.read!(&1)))
    |> Enum.flat_map(&String.split/1)
    |> MapSet.new()
  end

  defp defined do
    stylesheet_names(@selector)
  end

  defp stylesheet_names(regex) do
    @stylesheets
    |> Enum.flat_map(&names(regex, selectors_only(File.read!(&1))))
    |> MapSet.new()
  end

  defp selectors_only(stylesheet) do
    stylesheet |> String.replace(@not_selectors, " ") |> String.replace(@literal, " ")
  end

  defp names(regex, source) do
    regex |> Regex.scan(source) |> Enum.map(&List.last/1)
  end
end
