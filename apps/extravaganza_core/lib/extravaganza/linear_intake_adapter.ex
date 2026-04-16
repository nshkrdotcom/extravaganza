defmodule Extravaganza.LinearIntakeAdapter do
  @moduledoc """
  Thin Linear issue normalization and ingestion into the Mezzanine work surface.
  """

  alias Extravaganza.ProductBootstrap
  alias Mezzanine.Surfaces.ProgramSurface
  alias Mezzanine.Surfaces.WorkSurface

  @spec ingest_issue(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def ingest_issue(issue, opts \\ []) when is_map(issue) do
    with {:ok, profile} <- ProductBootstrap.ensure_bootstrapped(opts) do
      issue
      |> build_work_attrs(profile)
      |> WorkSurface.ingest_work()
    end
  end

  @spec build_work_attrs(map(), map()) :: map()
  def build_work_attrs(issue, %{config: config, program: program, work_class: work_class})
      when is_map(issue) do
    identifier = fetch(issue, :identifier) || fetch(issue, :id) || "unidentified"

    %{
      tenant_id: config.tenant_id,
      program_id: ProgramSurface.program_id(program),
      work_class_id: ProgramSurface.work_class_id(work_class),
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
