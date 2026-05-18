defmodule Extravaganza.TestSupport.LinearIssueFixture do
  @moduledoc false

  alias Extravaganza.{Config, Sources}

  @spec ingest_issue(map(), keyword()) :: {:ok, AppKit.Core.SubjectDetail.t()} | {:error, term()}
  def ingest_issue(issue, opts \\ []) when is_map(issue) do
    Sources.sync_issue_tracker_item(issue, opts)
  end

  @spec build_subject_attrs(map(), Config.t()) :: map()
  def build_subject_attrs(issue, %Config{} = config) when is_map(issue) do
    identifier = fetch(issue, :identifier) || fetch(issue, :id) || "unidentified"

    %{
      external_ref: "linear:#{identifier}",
      title: fetch(issue, :title) || identifier,
      description: fetch(issue, :description),
      source_kind: config.linear_source_kind,
      payload: %{"issue" => stringify_map(issue)},
      normalized_payload: %{
        "identifier" => identifier,
        "title" => fetch(issue, :title) || identifier,
        "description" => fetch(issue, :description),
        "state" => fetch(issue, :state),
        "team" => fetch(issue, :team),
        "labels" => fetch(issue, :labels) || [],
        "url" => fetch(issue, :url)
      }
    }
  end

  defp fetch(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp stringify_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_value(value)}
      {key, value} -> {key, stringify_value(value)}
    end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value
end
