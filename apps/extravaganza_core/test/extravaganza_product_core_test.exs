defmodule ExtravaganzaProductCoreTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RunRef
  alias Ecto.Adapters.SQL.Sandbox
  alias Extravaganza.{Config, LinearIntakeAdapter, ProductBootstrap, ThinHost}
  alias Mezzanine.OpsDomain.Repo

  setup do
    pid = Sandbox.start_owner!(Repo, shared: false)
    tenant_id = "extravaganza-test-#{System.unique_integer([:positive])}"

    on_exit(fn -> Sandbox.stop_owner(pid) end)

    {:ok, tenant_id: tenant_id}
  end

  test "loads normalized config and applies overrides" do
    config =
      Config.load(
        tenant_id: "tenant-override",
        program_name: "Operator Program",
        operator_surface_enabled?: false
      )

    assert config.tenant_id == "tenant-override"
    assert config.program_name == "Operator Program"
    assert config.operator_surface_enabled? == false
    assert config.program_slug == "extravaganza_coding_ops"
  end

  test "bootstrap is idempotent and updates the durable profile", %{tenant_id: tenant_id} do
    assert {:ok, first} = ProductBootstrap.ensure_bootstrapped(tenant_id: tenant_id)

    assert {:ok, second} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               program_name: "Updated Extravaganza Program",
               work_class_kind: "ops_coding_task",
               linear_source_kind: "linear_issue"
             )

    assert first.program.id == second.program.id
    assert first.policy_bundle.id == second.policy_bundle.id
    assert first.work_class.id == second.work_class.id
    assert first.placement_profile.id == second.placement_profile.id

    assert second.program.name == "Updated Extravaganza Program"
    assert second.program.configuration["intake"]["source_kind"] == "linear_issue"
    assert second.work_class.kind == "ops_coding_task"
    assert second.placement_profile.status == :active
  end

  test "linear intake upserts a single work object per external reference", %{
    tenant_id: tenant_id
  } do
    issue = %{
      id: "ENG-101",
      identifier: "ENG-101",
      title: "Investigate operator queue",
      description: "Trace queue latency",
      state: "Todo",
      labels: ["ops"],
      team: "Platform",
      url: "https://linear.app/example/issue/ENG-101"
    }

    assert {:ok, first_work} = LinearIntakeAdapter.ingest_issue(issue, tenant_id: tenant_id)

    assert first_work.external_ref == "linear:ENG-101"
    assert first_work.title == "Investigate operator queue"

    updated_issue =
      issue
      |> Map.put(:title, "Investigate operator queue hard failure")
      |> Map.put(:labels, ["ops", "incident"])

    assert {:ok, second_work} =
             LinearIntakeAdapter.ingest_issue(updated_issue, tenant_id: tenant_id)

    assert second_work.id == first_work.id
    assert second_work.title == "Investigate operator queue hard failure"
    assert second_work.normalized_payload["labels"] == ["ops", "incident"]
  end

  test "thin host starts a run through the mezzanine-backed app kit path", %{tenant_id: tenant_id} do
    assert {:ok, result} =
             ThinHost.start_run(
               %{
                 external_ref: "linear:ENG-202",
                 title: "Ship operator shell slice",
                 description: "Drive the thin-host path",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-202"},
                 normalized_payload: %{"issue_id" => "ENG-202"}
               },
               tenant_id: tenant_id
             )

    assert result.surface == :work_control
    assert result.state == :waiting_review
    assert %RunRef{} = result.payload.run_ref
    assert result.payload.run_ref.metadata.tenant_id == tenant_id
    assert is_binary(result.payload.work_object_id)

    assert {:ok, status} = ThinHost.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert status.work_object_id == result.payload.work_object_id
    assert is_list(status.timeline)
    assert is_map(status.gate_status)
  end
end
