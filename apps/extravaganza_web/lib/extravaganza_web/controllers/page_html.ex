defmodule ExtravaganzaWeb.PageHTML do
  @moduledoc false

  use ExtravaganzaWeb, :html

  embed_templates("page_html/*")

  def dashboard_map(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  def dashboard_map(_map, _key), do: %{}

  def dashboard_list(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_list(value) -> value
      _value -> []
    end
  end

  def dashboard_list(_map, _key), do: []

  def format_dashboard_int(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  def format_dashboard_int(value) when is_binary(value), do: value
  def format_dashboard_int(_value), do: "0"

  def format_dashboard_tps(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 2) <> " tps"
  end

  def format_dashboard_tps(value) when is_integer(value) do
    format_dashboard_tps(value / 1)
  end

  def format_dashboard_tps(_value), do: "0.00 tps"
end
