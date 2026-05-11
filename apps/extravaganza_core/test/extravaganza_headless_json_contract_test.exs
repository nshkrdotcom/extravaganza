defmodule Extravaganza.HeadlessJSONContractTest do
  use ExUnit.Case, async: false

  alias Extravaganza.{HeadlessJSON, HeadlessSurface}
  alias Extravaganza.Presenters.{EventPresenter, EvidencePresenter, RunPresenter}
  alias Extravaganza.TestSupport.FakeHeadlessBackend

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)
    Application.put_env(:app_kit_core, :headless_backend, FakeHeadlessBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if is_nil(previous_fixture_context) do
        Application.delete_env(:extravaganza_core, :headless_fixture_context?)
      else
        Application.put_env(
          :extravaganza_core,
          :headless_fixture_context?,
          previous_fixture_context
        )
      end
    end)
  end

  test "success envelopes include stable refs without raw lower/provider material" do
    assert {:ok, run} = HeadlessSurface.run_detail("run:fixture")

    envelope =
      "run_detail"
      |> HeadlessJSON.success(RunPresenter.present(run), %{
        trace_id: "trace:test",
        idempotency_key: "idem:test",
        generated_at: "2026-05-08T00:00:00Z"
      })

    assert envelope["ok"] == true
    assert envelope["schema"] == "extravaganza.headless.response.v1"
    assert envelope["operation"] == "run_detail"
    assert envelope["trace_id"] == "trace:test"
    assert envelope["idempotency_key"] == "idem:test"
    assert envelope["runtime_profile_ref"] == "runtime-profile:local-deterministic"
    assert envelope["refs"]["run_ref"] == "run:fixture"
    assert envelope["refs"]["authority_ref"] == "authority:fixture"
    assert envelope["refs"]["connector_manifest_ref"] == "manifest:fixture"
    assert envelope["refs"]["capability_negotiation_ref"] == "capability-negotiation:fixture"
    assert envelope["refs"]["lower_request_ref"] == "lower-request:fixture"
    assert envelope["refs"]["lower_receipt_ref"] == "lower-receipt:fixture"

    encoded = Jason.encode!(envelope)
    refute String.contains?(encoded, "api_key")
    refute String.contains?(encoded, "provider_payload")
    refute String.contains?(encoded, "workspace_path")
    refute String.contains?(encoded, "/home/")
  end

  test "success envelopes redact absolute workspace roots and cwd values" do
    envelope =
      HeadlessJSON.success(
        "workspace_readback",
        %{
          workspace: %{
            workspace_root: "/tmp/extravaganza/subject-1",
            cwd: "/tmp/extravaganza/subject-1",
            workspace_ref: "workspace://tenant-1/subject-1",
            path_redacted?: true
          }
        },
        generated_at: "2026-05-08T00:00:00Z"
      )

    encoded = Jason.encode!(envelope)

    refute String.contains?(encoded, "/tmp/extravaganza")
    assert String.contains?(encoded, "[redacted-path]")

    assert get_in(envelope, ["data", "workspace", "workspace_ref"]) ==
             "workspace://tenant-1/subject-1"
  end

  test "evidence chain and event page are first-class headless readback operations" do
    assert {:ok, evidence_chain} = HeadlessSurface.evidence_chain("run:fixture")
    evidence = EvidencePresenter.present(evidence_chain)

    assert evidence["schema_ref"] == "headless_evidence_chain.v1"
    assert evidence["data"]["lower"]["lower_runtime_kind"] == "deterministic_fixture"
    assert evidence["data"]["governance"]["authority_ref"] == "authority:fixture"

    assert evidence["data"]["source_publication"]["source_publication_receipt_ref"] ==
             "source-publication:fixture"

    assert {:ok, event_page} = HeadlessSurface.events(%{"run_id" => "run:fixture"})
    events = EventPresenter.present_page(event_page)

    assert events["schema_ref"] == "headless_events.v1"

    assert Enum.map(events["data"]["entries"], & &1["event_ref"]) == [
             "event:run:1",
             "event:run:2"
           ]
  end

  test "error envelopes classify readback failures and preserve retry guidance" do
    envelope =
      HeadlessJSON.error("run_detail", :runtime_projection_not_found,
        trace_id: "trace:error",
        generated_at: "2026-05-08T00:00:00Z"
      )

    assert envelope["ok"] == false
    assert envelope["schema"] == "extravaganza.headless.error.v1"
    assert envelope["operation"] == "run_detail"
    assert envelope["error"]["code"] == "projection_unavailable"
    assert envelope["error"]["class"] == "readback_unavailable"
    assert envelope["error"]["retryable"] == true
    assert envelope["error"]["missing_refs"] == ["projection_ref"]
  end
end
