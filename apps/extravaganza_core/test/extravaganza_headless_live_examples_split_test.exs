defmodule Extravaganza.HeadlessLiveExamplesSplitTest do
  use ExUnit.Case, async: true

  alias Extravaganza.HeadlessLiveExamples.{Credentials, Envelope, Lanes, Registry}

  test "registry exposes live example descriptors in stable smoke and standalone order" do
    assert Registry.example_order() == [
             :linear_source,
             :linear_current_states,
             :codex_turn,
             :linear_publication,
             :linear_graphql_tool,
             :github_evidence
           ]

    assert Registry.standalone_examples() == Registry.example_order() ++ [:github_pr_cleanup]

    example = Registry.fetch!(:linear_source)
    assert example.operation == "live.linear-source"
    assert example.provider == "linear"
    assert example.credential_refs == ["LINEAR_API_KEY"]
    assert example.provider_effect == "source_intake"
  end

  test "credential preflight is redacted and classifies dispatchable bindings" do
    example = Registry.fetch!(:linear_source)

    preflight =
      Credentials.preflight(:linear_source, example, %{
        connection_id: "connection://linear/primary",
        credential_ref: "credential-ref-linear",
        credential_lease_ref: "credential-lease-linear",
        live_product_path?: true
      })

    assert preflight["status"] == "dispatchable"
    assert preflight["dispatch_binding"] == "connection_id"
    assert preflight["credential_source"] == "connection_id"
    assert preflight["credential_ref"] == "credential-ref-linear"
    assert preflight["credential_lease_ref"] == "credential-lease-linear"
    assert preflight["secret_material_redacted?"] == true
    refute Map.has_key?(preflight, "api_key")
  end

  test "credential preflight rejects credential refs without a connection binding" do
    example = Registry.fetch!(:linear_source)

    preflight =
      Credentials.preflight(:linear_source, example, %{
        credential_ref: "credential-ref-linear"
      })

    skip_reason = Credentials.skip_reason(:linear_source, example, %{credential_ref: "x"})

    assert preflight["status"] == "missing_dispatch_binding"
    assert preflight["credential_source"] == "credential_ref"
    assert skip_reason["code"] == "credential_ref_requires_connection_id"
  end

  test "envelope assembly preserves public fields and redaction policy" do
    example = Registry.fetch!(:linear_source)

    payload =
      Envelope.example_payload(
        :linear_source,
        example,
        %{
          "proof_source" => "fixture_headless_surface",
          "subject_ref" => "subject:fixture",
          "run_ref" => "run:fixture",
          "workflow_ref" => "workflow:fixture",
          "runtime_profile_ref" => "runtime-profile:fixture",
          "authority_ref" => "authority:fixture",
          "decision_ref" => "decision:fixture",
          "connector_manifest_ref" => "manifest:fixture",
          "capability_negotiation_ref" => "capability:fixture",
          "lower_request_ref" => "lower-request:fixture",
          "lower_receipt_ref" => "lower-receipt:fixture",
          "source_publication_ref" => "source-publication:fixture",
          "evidence_chain_ref" => "evidence:fixture",
          "event_page_ref" => "events:fixture",
          "readback_count" => 1
        },
        %{
          fixture: "headless_live",
          trace_id: "trace://phase11",
          api_key: "secret-value"
        },
        %{
          "provider" => "linear",
          "effect" => "source_intake",
          "status" => "receipt_recorded",
          "lower_request_ref" => "lower-request://linear/source",
          "lower_receipt_ref" => "lower-receipt://linear/source",
          "route_evidence" => %{"route" => "ok"},
          "provider_request_sent?" => true
        }
      )

    assert payload["operation"] == "live.linear-source"
    assert payload["status"] == "completed"
    assert payload["trace_id"] == "trace://phase11"
    assert payload["credential_preflight"]["secret_material_redacted?"] == true
    assert payload["lower_request_ref"] == "lower-request://linear/source"
    assert payload["lower_receipt_ref"] == "lower-receipt://linear/source"

    assert payload["product_path"]["entrypoint"] ==
             "Extravaganza.ProductHost.live_linear_source_example"

    refute Jason.encode!(payload) =~ "secret-value"
  end

  test "lane dispatcher records skipped route evidence without exposing secrets" do
    example = Registry.fetch!(:linear_source)

    provider_effect =
      Lanes.effect(
        :linear_source,
        example,
        %{
          "proof_source" => "fixture_headless_surface",
          "authority_ref" => "authority:fixture",
          "readback_count" => 1
        },
        %{trace_id: "trace://phase11-lane", api_key: "secret-value"}
      )

    assert provider_effect["status"] == "skipped"
    assert provider_effect["fixture_backed?"] == true
    assert provider_effect["credential_preflight"]["status"] == "fixture_only"
    assert provider_effect["route_evidence"]["trace_ref"] == "trace://phase11-lane"

    assert provider_effect["route_evidence"]["product_role_ref"] ==
             "source-role://extravaganza/issue-tracker"

    refute Jason.encode!(provider_effect) =~ "secret-value"
  end
end
