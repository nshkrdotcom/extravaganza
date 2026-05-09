defmodule Extravaganza.HeadlessReadback do
  @moduledoc false

  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail

  @spec evidence_chain(struct()) :: map()
  def evidence_chain(%RuntimeRunDetail{} = run) do
    run_data = RuntimeRunDetail.dump(run)
    runtime_row = Map.get(run_data, "runtime_row", %{})
    extensions = Map.get(runtime_row, "extensions", %{})
    run_ref = Map.get(run_data, "run_ref")

    %{
      "schema_ref" => "headless_evidence_chain.v1",
      "schema_version" => 1,
      "evidence_chain_ref" => "evidence-chain:#{safe_suffix(run_ref)}",
      "run_ref" => run_ref,
      "subject_ref" => Map.get(runtime_row, "subject_ref"),
      "runtime_profile_ref" => get_in(extensions, ["governance", "runtime_profile_ref"]),
      "governance" => Map.get(extensions, "governance", %{}),
      "lower" => Map.get(extensions, "lower_envelope", %{}),
      "lower_receipt" => Map.get(extensions, "lower_receipt", %{}),
      "retry_receipts" => Map.get(extensions, "retry_receipts", []),
      "incident_bundles" => Map.get(extensions, "incident_bundles", []),
      "acceptance" => Map.get(extensions, "acceptance", %{}),
      "source_publication" => Map.get(extensions, "source_publication", %{}),
      "events" => Map.get(run_data, "events", []),
      "diagnostics" => Map.get(run_data, "diagnostics", [])
    }
    |> compact()
  end

  @spec event_page(struct(), map()) :: map()
  def event_page(%RuntimeRunDetail{} = run, params \\ %{}) when is_map(params) do
    run_data = RuntimeRunDetail.dump(run)
    entries = Map.get(run_data, "events", [])

    %{
      "schema_ref" => "headless_events.v1",
      "schema_version" => 1,
      "event_page_ref" => "event-page:#{safe_suffix(Map.get(run_data, "run_ref"))}",
      "run_ref" => Map.get(run_data, "run_ref"),
      "entries" => entries,
      "page" => %{
        "page_size" => length(entries),
        "cursor" => Map.get(params, "cursor") || Map.get(params, :cursor),
        "total_entries" => length(entries)
      }
    }
  end

  defp compact(%{} = map), do: Map.reject(map, fn {_key, value} -> value in [nil, %{}, []] end)

  defp safe_suffix(nil), do: "unknown"

  defp safe_suffix(value) when is_binary(value) do
    value
    |> String.replace("://", ":")
    |> String.replace("/", ":")
  end
end

defmodule Extravaganza.Presenters.EvidencePresenter do
  @moduledoc "Shared evidence-chain presenter."

  alias Extravaganza.HeadlessJSON

  @spec present(map(), keyword()) :: map()
  def present(chain, opts \\ []) when is_map(chain) do
    %{
      "schema_ref" => "headless_evidence_chain.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => HeadlessJSON.sanitize(chain)
    }
  end
end

defmodule Extravaganza.Presenters.EventPresenter do
  @moduledoc "Shared event-page presenter."

  alias Extravaganza.HeadlessJSON

  @spec present_page(map(), keyword()) :: map()
  def present_page(page, opts \\ []) when is_map(page) do
    %{
      "schema_ref" => "headless_events.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => HeadlessJSON.sanitize(page)
    }
  end
end
