defmodule Extravaganza.HeadlessSurfaceTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RuntimeReadback.{CommandResult, RuntimeRunDetail, RuntimeStateSnapshot}
  alias Extravaganza.{HeadlessSurface, ProductPack}

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    RunPresenter,
    StatePresenter,
    SubjectPresenter
  }

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

  test "product pack declares Phase 4 profile slots without requiring M2" do
    slots = ProductPack.profile_slots([])

    assert slots.source_profile_ref == :linear_coding_task
    assert slots.runtime_profile_ref == :codex_session
    assert slots.memory_profile_ref == :none
    assert slots.projection_profile_ref == :coding_ops_projection_v1
  end

  test "HeadlessSurface reads fixture M1 state through AppKit only" do
    assert {:ok, %RuntimeStateSnapshot{} = snapshot} = HeadlessSurface.state_snapshot(%{})

    states = Enum.map(snapshot.rows, & &1.state)

    assert "running" in states
    assert "retrying" in states
    assert "review_pending" in states
    assert "terminal_success" in states
    assert "terminal_failure" in states
    assert "input_required" in states
    assert "approval_required" in states
    assert "cancelled" in states
    assert "authority_denied" in states

    rendered = StatePresenter.present(snapshot, correlation_id: "corr:test")

    assert rendered["schema_ref"] == "headless_state_snapshot.v1"
    assert rendered["correlation_id"] == "corr:test"
    assert rendered["data"]["turns"] == []
    refute Jason.encode!(rendered) =~ "workspace_path"
    refute Jason.encode!(rendered) =~ "/home/"
  end

  test "subject and run presenters pass through future M2 event slots safely" do
    assert {:ok, subject} = HeadlessSurface.subject_detail("subject:fixture")
    rendered_subject = SubjectPresenter.present(subject)

    event_kinds = Enum.map(rendered_subject["data"]["events"], & &1["event_kind"])
    assert "future_m2_state_added" in event_kinds
    assert rendered_subject["data"]["agent_loop_diagnostics"] == []

    assert {:ok, %RuntimeRunDetail{} = run} = HeadlessSurface.run_detail("run:fixture")
    rendered_run = RunPresenter.present(run)

    assert Enum.map(rendered_run["data"]["events"], & &1["event_seq"]) == [1, 2]
    assert rendered_run["data"]["memory_proof_refs"] == []
  end

  test "refresh and control commands return typed command results" do
    assert {:ok, %CommandResult{} = refresh} =
             HeadlessSurface.request_refresh(%{"idempotency_key" => "idem:refresh"})

    assert refresh.command_kind == "refresh"
    assert refresh.workflow_effect_state == "pending_signal"

    assert {:ok, %CommandResult{} = denied} =
             HeadlessSurface.request_control("subject:fixture", "cancel", %{
               "idempotency_key" => "idem:cancel",
               "deny" => "true"
             })

    assert denied.accepted? == false
    assert denied.workflow_effect_state == "rejected_by_authority"
    assert List.last(denied.authority_refs) == "authority:decision-denied"

    rendered = CommandResultPresenter.present(denied, correlation_id: "corr:denied")
    assert rendered["schema_ref"] == "headless_command_result.v1"
  end

  test "offline M1 receipt validates the required proof taxonomy" do
    receipt =
      "test/fixtures/receipts/agentic_substrate_headless_e2e_v1.json"
      |> File.read!()
      |> Jason.decode!()

    assert receipt["schema_ref"] == "agentic_substrate_headless_e2e_v1"
    assert receipt["mechanism"] == "M1"
    assert receipt["agent_loop_used?"] == false
    assert receipt["memory_profile_ref"] == "none"
    assert receipt["provider_credentials_required?"] == false
    assert receipt["network_required?"] == false
    assert receipt["receipt_state"] == "proven"
  end
end

defmodule Extravaganza.HeadlessSharedPresenterBoundaryTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "browser and API controllers import the shared headless presenters" do
    browser =
      File.read!(
        Path.join(@root, "extravaganza_web/lib/extravaganza_web/controllers/page_controller.ex")
      )

    api =
      File.read!(
        Path.join(
          @root,
          "extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex"
        )
      )

    assert browser =~ "StatePresenter"
    assert browser =~ "SubjectPresenter"
    assert browser =~ "ReviewPresenter"

    assert api =~ "StatePresenter"
    assert api =~ "SubjectPresenter"
    assert api =~ "RunPresenter"
    assert api =~ "CommandResultPresenter"
  end
end
