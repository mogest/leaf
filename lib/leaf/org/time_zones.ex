defmodule Leaf.Org.TimeZones do
  @moduledoc """
  Which time zones a country keeps.

  Read at compile time from the table shipped with the zone database the app resolves times
  against, so what a calendar can be offered is what `DateTime` can actually read it in. It is the
  civil list: a zone that has behaved identically since 1970 is not offered twice under two names.
  """

  @table :tz
         |> Application.app_dir("priv")
         |> Path.join("tzdata*/zone1970.tab")
         |> Path.wildcard()
         |> List.first()

  @external_resource @table

  @places @table
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.reject(&String.starts_with?(&1, "#"))
          |> Enum.flat_map(fn row ->
            [countries, _coordinates, zone | _comment] = String.split(row, "\t")

            countries |> String.split(",") |> Enum.map(&{&1, zone})
          end)

  # Somebody on no calendar is read in UTC, so it is a zone a calendar may say it keeps.
  @all @places |> Enum.map(&elem(&1, 1)) |> Enum.concat(["Etc/UTC"]) |> Enum.sort() |> Enum.uniq()

  @by_country Map.new(Enum.group_by(@places, &elem(&1, 0), &elem(&1, 1)), fn {country, zones} ->
                {country, Enum.sort(zones)}
              end)

  @doc "The zones kept in `country_code`, or every zone where that country is not one we know."
  @spec of(String.t() | nil) :: [String.t()]
  def of(nil), do: @all
  def of(country_code), do: Map.get(@by_country, String.upcase(country_code), @all)
end
