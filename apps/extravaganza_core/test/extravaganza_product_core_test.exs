defmodule ExtravaganzaProductCoreTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RunRef
  alias Ecto.Adapters.SQL.Sandbox
  alias ExtravaganzaCore.MixProject, as: CoreMixProject

  alias Extravaganza.{
    Config,
    LinearIntakeAdapter,
    ProductBootstrap,
    ProductPack,
    Queries,
    Reviews,
    ThinHost,
    Workflows
  }

  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.ConfigRegistry.Repo, as: ConfigRegistryRepo
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.EvidenceLedger.Repo, as: EvidenceRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.OpsDomain.Repo
  alias Mezzanine.Pack.Compiler

  setup do
    owners = [
      Sandbox.start_owner!(Repo, shared: false),
      Sandbox.start_owner!(ConfigRegistryRepo, shared: true),
      Sandbox.start_owner!(AuditRepo, shared: false),
      Sandbox.start_owner!(ExecutionRepo, shared: false),
      Sandbox.start_owner!(DecisionsRepo, shared: false),
      Sandbox.start_owner!(EvidenceRepo, shared: false)
    ]

    [_ops_owner, config_owner | _rest] = owners
    allow_registry_process(config_owner)

    tenant_id = "extravaganza-test-#{Ecto.UUID.generate()}"
    pack_version = "1.0.0"

    on_exit(fn -> Enum.each(owners, &Sandbox.stop_owner/1) end)

    {:ok, tenant_id: tenant_id, pack_version: pack_version}
  end

  test "extravaganza core no longer depends on mezzanine program surface" do
    refute Enum.any?(CoreMixProject.project()[:deps], fn
             {:mezzanine_program_surface, _opts} -> true
             {:mezzanine_program_surface, _req, _opts} -> true
             _other -> false
           end)
  end

  test "loads normalized config and applies overrides" do
    config =
      Config.load(
        tenant_id: "tenant-override",
        program_name: "Operator Program",
        operator_surface_enabled?: false,
        pack_version: "9.9.9",
        execution_timeout_ms: 123_000
      )

    assert config.tenant_id == "tenant-override"
    assert config.program_name == "Operator Program"
    assert config.operator_surface_enabled? == false
    assert config.program_slug == "extravaganza_coding_ops"
    assert config.pack_version == "9.9.9"
    assert config.execution_timeout_ms == 123_000
  end

  test "bootstrap is idempotent and updates the durable installation profile", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, first} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, second} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version,
               execution_timeout_ms: 180_000
             )

    assert first.installation_ref.id == second.installation_ref.id
    assert first.install_result.status == :created
    assert second.install_result.status in [:reused, :updated]
    assert first.installation_ref.pack_slug == "extravaganza_coding_ops"
    assert second.installation_ref.pack_version == pack_version
    assert second.installation_ref.compiled_pack_revision == 2

    assert get_in(
             second.install_result.metadata.installation.bindings,
             ["execution_bindings", "coding_operations", "execution_params", "timeout_ms"]
           ) == 180_000
  end

  test "linear intake upserts a single work object per external reference", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

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

    assert {:ok, first_subject} =
             LinearIntakeAdapter.ingest_issue(
               issue,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert first_subject.payload.external_ref == "linear:ENG-101"
    assert first_subject.title == "Investigate operator queue"

    updated_issue =
      issue
      |> Map.put(:title, "Investigate operator queue hard failure")
      |> Map.put(:labels, ["ops", "incident"])

    assert {:ok, second_subject} =
             LinearIntakeAdapter.ingest_issue(
               updated_issue,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert second_subject.subject_ref.id == first_subject.subject_ref.id
    assert second_subject.title == "Investigate operator queue hard failure"
    assert second_subject.payload.external_ref == "linear:ENG-101"
  end

  test "product-local facades start a run and expose operator status through app kit", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-202",
                 title: "Ship operator shell slice",
                 description: "Drive the thin-host path",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-202"},
                 normalized_payload: %{"issue_id" => "ENG-202"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert result.surface == :work_control
    assert result.state == :waiting_review
    assert %RunRef{} = result.payload.run_ref
    assert result.payload.run_ref.metadata.tenant_id == tenant_id
    assert is_binary(result.payload.work_object_id)

    assert {:ok, status} = Queries.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert status.work_object_id == result.payload.work_object_id
    assert is_list(status.timeline)
    assert is_map(status.gate_status)
  end

  test "product-local query facade lists the operator queue through app kit", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _first} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-505",
                 title: "Queue item alpha",
                 description: "First queue item",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-505"},
                 normalized_payload: %{"issue_id" => "ENG-505"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, _second} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-506",
                 title: "Queue item beta",
                 description: "Second queue item",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-506"},
                 normalized_payload: %{"issue_id" => "ENG-506"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, queue} =
             Queries.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    assert Enum.any?(queue.page.entries, &(&1.title == "Queue item alpha"))
    assert Enum.any?(queue.page.entries, &(&1.title == "Queue item beta"))
    assert is_map(queue.stats)
  end

  test "product-local review queue lists pending decisions and records acceptance", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-507",
                 title: "Approve review queue item",
                 description: "Drive the review queue facade",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-507"},
                 normalized_payload: %{"issue_id" => "ENG-507"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, reviews_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    pending_review = hd(reviews_page.page.entries)

    assert pending_review.summary == "Approve review queue item"

    assert {:ok, action_result} =
             Reviews.record_pending_decision(
               %{
                 id: pending_review.decision_ref.id,
                 decision_kind: pending_review.decision_ref.decision_kind,
                 subject_id: pending_review.subject_ref.id,
                 subject_kind: pending_review.subject_ref.subject_kind
               },
               %{decision: :accept, reason: "accepted from product core test"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert action_result.status == :completed

    assert {:ok, after_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    refute Enum.any?(
             after_page.page.entries,
             &(&1.decision_ref.id == pending_review.decision_ref.id)
           )
  end

  test "product-local review facade routes run review through the app kit path", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-303",
                 title: "Review operator decision",
                 description: "Drive the product-local review facade",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-303"},
                 normalized_payload: %{"issue_id" => "ENG-303"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, review} =
             Reviews.review_run(
               result.payload.run_ref,
               %{kind: :operator_note, summary: "safe to proceed"},
               tenant_id: tenant_id
             )

    assert review.decision.state == :approved
    assert review.review_unit.status == :accepted
  end

  test "thin host remains a compatibility wrapper over the product-local facades", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ThinHost.start_run(
               %{
                 external_ref: "linear:ENG-404",
                 title: "Legacy thin-host caller",
                 description: "Confirm wrapper compatibility",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-404"},
                 normalized_payload: %{"issue_id" => "ENG-404"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, status} = ThinHost.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert {:ok, review} =
             ThinHost.review_run(
               result.payload.run_ref,
               %{kind: :operator_note, summary: "legacy wrapper approval"},
               tenant_id: tenant_id
             )

    assert status.work_object_id == result.payload.work_object_id
    assert review.decision.state == :approved
  end

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
    end
  end

  defp allow_registry_process(config_owner) do
    case Process.whereis(Mezzanine.Pack.Registry) do
      pid when is_pid(pid) -> Sandbox.allow(ConfigRegistryRepo, config_owner, pid)
      _other -> :ok
    end
  end
end
