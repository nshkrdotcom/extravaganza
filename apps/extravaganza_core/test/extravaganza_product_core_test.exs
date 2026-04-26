defmodule ExtravaganzaProductCoreTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RunRef
  alias Ecto.Adapters.SQL.Sandbox
  alias ExtravaganzaCore.MixProject, as: CoreMixProject

  alias Extravaganza.{
    Config,
    ProductBootstrap,
    ProductHost,
    ProductPack,
    Queries,
    Reviews,
    Workflows
  }

  alias Extravaganza.TestSupport.ExecutionTraceFixture
  alias Extravaganza.TestSupport.LinearIssueFixture

  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.ConfigRegistry.Repo, as: ConfigRegistryRepo
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.EvidenceLedger.Repo, as: EvidenceRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Execution.RuntimeStack
  alias Mezzanine.Pack.Compiler

  setup do
    owners = [
      Sandbox.start_owner!(RuntimeStack.ops_domain_repo(), shared: false),
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

  test "extravaganza core declares the pure pack-model contract without widening runtime deps" do
    deps = CoreMixProject.project()[:deps]

    assert Enum.any?(deps, fn
             {:mezzanine_pack_model, _opts} -> true
             {:mezzanine_pack_model, _req, _opts} -> true
             _other -> false
           end)

    refute Enum.any?(deps, fn
             {:mezzanine_pack_compiler, _opts} -> true
             {:mezzanine_pack_compiler, _req, _opts} -> true
             {:mezzanine_config_registry, _opts} -> true
             {:mezzanine_config_registry, _req, _opts} -> true
             {:mezzanine_execution_engine, _opts} -> true
             {:mezzanine_execution_engine, _req, _opts} -> true
             {:mezzanine_integration_bridge, _opts} -> true
             {:mezzanine_integration_bridge, _req, _opts} -> true
             _other -> false
           end)
  end

  test "product identity reports app kit as the operational downstream path" do
    assert %{
             downstream: [:app_kit],
             pack_contract: :mezzanine_pack_model,
             posture: :operator_proving_ground,
             role: :proving_ground_product
           } = Extravaganza.identity()
  end

  test "product runtime does not hardcode app kit bridge implementations" do
    refute File.exists?(Path.expand("../lib/extravaganza/app_kit_backends.ex", __DIR__))

    [
      Path.expand("../lib/extravaganza/application.ex", __DIR__),
      Path.expand("../lib/extravaganza/product_surface.ex", __DIR__)
    ]
    |> Enum.each(fn path ->
      contents = File.read!(path)

      refute contents =~ "AppKit.Bridges.MezzanineBridge",
             "#{path} still hardcodes the AppKit mezzanine bridge"

      refute contents =~ "AppKitBackends.ensure_configured",
             "#{path} still configures AppKit backends from product code"
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

  test "fixture source ingest upserts a single subject per external reference", %{
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
             LinearIssueFixture.ingest_issue(
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
             LinearIssueFixture.ingest_issue(
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
                 description: "Drive the operator-host path",
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

  test "product-local review queue lists pending decisions and records accept, reject, and waive decisions",
       %{
         tenant_id: tenant_id,
         pack_version: pack_version
       } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    review_opts = [tenant_id: tenant_id, pack_version: pack_version]

    start_reviewable_work!(
      "linear:ENG-507",
      "Approve review queue item",
      review_opts
    )

    assert {:ok, reviews_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    pending_review = hd(reviews_page.page.entries)

    assert pending_review.summary == "Approve review queue item"

    assert {:ok, accept_result} =
             Reviews.record_review_decision(
               review_identity(pending_review),
               %{decision: :accept, reason: "accepted from product core test"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert accept_result.status == :completed
    assert accept_result.action_ref.action_kind == "review_accept"

    reject_review =
      start_reviewable_work!(
        "linear:ENG-508",
        "Reject review queue item",
        review_opts
      )

    assert {:ok, reject_result} =
             Reviews.record_review_decision(
               review_identity(reject_review),
               %{decision: :reject, reason: "rejected from product core test"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert reject_result.status == :completed
    assert reject_result.action_ref.action_kind == "review_reject"

    waive_review =
      start_reviewable_work!(
        "linear:ENG-509",
        "Waive review queue item",
        review_opts
      )

    assert {:ok, waive_result} =
             Reviews.record_review_decision(
               review_identity(waive_review),
               %{decision: :waive, reason: "waived from product core test"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert waive_result.status == :completed
    assert waive_result.action_ref.action_kind == "review_waive"

    assert {:ok, after_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    closed_review_ids = [
      pending_review.decision_ref.id,
      reject_review.decision_ref.id,
      waive_review.decision_ref.id
    ]

    refute Enum.any?(
             after_page.page.entries,
             &(&1.decision_ref.id in closed_review_ids)
           )
  end

  test "product-local operator detail exposes actions, trace, and leased read surfaces", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-808",
                 title: "Inspect operator detail",
                 description: "Drive subject detail and lease issuance",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-808"},
                 normalized_payload: %{"issue_id" => "ENG-808"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, queue} =
             ProductHost.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    subject_id = hd(queue.page.entries).subject_ref.id

    installation_id =
      bootstrapped_installation_id!(tenant_id: tenant_id, pack_version: pack_version)

    %{execution_id: execution_id} =
      ExecutionTraceFixture.seed_execution_trace!(
        tenant_id: tenant_id,
        installation_id: installation_id,
        subject_id: subject_id
      )

    assert {:ok, detail} =
             ProductHost.subject_detail(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert detail.subject.title == "Inspect operator detail"
    assert detail.subject.current_execution_ref.id == execution_id
    assert Enum.any?(detail.actions, &(&1.action_ref.action_kind == "pause"))
    assert Enum.any?(detail.timeline, &(&1.event_kind == "run_scheduled"))
    assert detail.trace_error == nil
    assert is_binary(detail.unified_trace.trace_id)

    assert {:ok, read_lease} =
             ProductHost.issue_read_lease(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert read_lease.lease_ref.execution_ref.id == detail.subject.current_execution_ref.id
    assert "fetch_run" in read_lease.allowed_operations

    assert {:ok, stream_attach_lease} =
             ProductHost.issue_stream_attach_lease(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert stream_attach_lease.lease_ref.execution_ref.id ==
             detail.subject.current_execution_ref.id

    assert stream_attach_lease.reconnect_cursor >= 0
  end

  test "subject detail keeps latest execution lineage visible after terminal operator control", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-810",
                 title: "Explain cancelled lineage",
                 description: "Keep trace and lineage visible after operator cancellation",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-810"},
                 normalized_payload: %{"issue_id" => "ENG-810"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, queue} =
             ProductHost.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    subject_id = hd(queue.page.entries).subject_ref.id

    installation_id =
      bootstrapped_installation_id!(tenant_id: tenant_id, pack_version: pack_version)

    supersedes_execution_id = Ecto.UUID.generate()
    barrier_id = Ecto.UUID.generate()

    seeded_trace =
      ExecutionTraceFixture.seed_execution_trace!(
        tenant_id: tenant_id,
        installation_id: installation_id,
        subject_id: subject_id,
        execution_attrs: %{
          supersedes_execution_id: supersedes_execution_id,
          barrier_id: barrier_id,
          last_reconcile_wave_id: "wave-1"
        },
        extra_audit_facts: [
          %{
            fact_kind: "execution_recovered",
            payload: %{
              "classification" => "reconciled",
              "last_reconcile_wave_id" => "wave-1"
            }
          },
          %{
            fact_kind: "execution_joined",
            payload: %{
              "join_step_ref" => "triage_join",
              "completed_children" => 2,
              "expected_children" => 2,
              "barrier_id" => barrier_id
            }
          }
        ]
      )

    assert {:ok, _read_lease} =
             ProductHost.issue_read_lease(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, cancel_result} =
             ProductHost.apply_subject_action(
               subject_id,
               :cancel,
               %{reason: "cancel with lineage proof"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert cancel_result.status == :completed

    assert {:ok, detail} =
             ProductHost.subject_detail(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert detail.subject.lifecycle_state == "cancelled"
    assert detail.subject.current_execution_ref == nil
    assert detail.unified_trace.trace_id == seeded_trace.trace_id
    assert detail.lineage_summary.current_dispatch_state == "cancelled"

    assert has_lineage_marker?(detail.lineage_summary.markers, "Classification", "accepted")
    assert has_lineage_marker?(detail.lineage_summary.markers, "Classification", "reconciled")

    assert has_lineage_marker?(
             detail.lineage_summary.markers,
             "Classification",
             "operator_cancelled"
           )

    assert has_lineage_marker?(
             detail.lineage_summary.markers,
             "Supersedes execution",
             supersedes_execution_id
           )

    assert has_lineage_marker?(detail.lineage_summary.markers, "Join barrier", barrier_id)
    assert has_lineage_marker?(detail.lineage_summary.markers, "Join step", "triage_join")
    assert has_lineage_marker?(detail.lineage_summary.markers, "Join progress", "2/2")
    assert has_lineage_marker?(detail.lineage_summary.markers, "Invalidated leases", "1")
    assert has_lineage_marker?(detail.lineage_summary.markers, "Reconcile wave", "wave-1")
  end

  test "product host applies operator actions and exposes resumed control posture", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-809",
                 title: "Pause and resume work",
                 description: "Drive operator controls through the product host",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-809"},
                 normalized_payload: %{"issue_id" => "ENG-809"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, queue} =
             ProductHost.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    subject_id = hd(queue.page.entries).subject_ref.id

    assert {:ok, pause_result} =
             ProductHost.apply_subject_action(
               subject_id,
               :pause,
               %{reason: "pause from product host"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert pause_result.status == :completed

    assert {:ok, paused_detail} =
             ProductHost.subject_detail(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert paused_detail.subject.payload.control_mode == "paused"
    assert Enum.any?(paused_detail.actions, &(&1.action_ref.action_kind == "resume"))

    assert {:ok, resume_result} =
             ProductHost.apply_subject_action(
               subject_id,
               :resume,
               %{reason: "resume from product host"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert resume_result.status == :completed

    assert {:ok, resumed_detail} =
             ProductHost.subject_detail(subject_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    refute resumed_detail.subject.payload.control_mode == "paused"
    assert Enum.any?(resumed_detail.actions, &(&1.action_ref.action_kind == "pause"))

    assert {:ok, cancel_result} =
             ProductHost.apply_subject_action(
               subject_id,
               :cancel,
               %{reason: "cancel from product host"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert cancel_result.status == :completed
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

  test "product host routes the current product-local facades through app kit", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-404",
                 title: "Product-host caller",
                 description: "Confirm the current product-host surface",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-404"},
                 normalized_payload: %{"issue_id" => "ENG-404"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, status} =
             ProductHost.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert {:ok, review} =
             ProductHost.review_run(
               result.payload.run_ref,
               %{kind: :operator_note, summary: "product-host approval"},
               tenant_id: tenant_id
             )

    assert status.work_object_id == result.payload.work_object_id
    assert review.decision.state == :approved

    assert {:ok, queue} =
             ProductHost.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    assert Enum.any?(queue.page.entries, &(&1.subject_ref.id == result.payload.work_object_id))
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

  defp bootstrapped_installation_id!(opts) do
    assert {:ok, profile} = ProductBootstrap.ensure_bootstrapped(opts)
    profile.installation_ref.id
  end

  defp start_reviewable_work!(external_ref, title, opts) do
    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: external_ref,
                 title: title,
                 description: "Drive the review queue facade",
                 source_kind: "linear",
                 payload: %{"issue_id" => external_ref},
                 normalized_payload: %{"issue_id" => external_ref}
               },
               opts
             )

    assert {:ok, reviews_page} = Queries.pending_reviews(%{}, opts)

    Enum.find(reviews_page.page.entries, &(&1.summary == title)) ||
      flunk("expected pending review for #{inspect(title)}")
  end

  defp review_identity(pending_review) do
    %{
      id: pending_review.decision_ref.id,
      decision_kind: pending_review.decision_ref.decision_kind,
      subject_id: pending_review.subject_ref.id,
      subject_kind: pending_review.subject_ref.subject_kind
    }
  end

  defp has_lineage_marker?(markers, label, value) do
    Enum.any?(markers, &(&1.label == label and &1.value == value))
  end

  defp allow_registry_process(config_owner) do
    case Process.whereis(Mezzanine.Pack.Registry) do
      pid when is_pid(pid) -> Sandbox.allow(ConfigRegistryRepo, config_owner, pid)
      _other -> :ok
    end
  end
end
