defmodule ExtravaganzaProductCoreTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.{
    DecisionRef,
    EvidenceProjection,
    ExecutionRef,
    ExecutionStateProjection,
    LowerReceiptSummary,
    ReviewProjection,
    RunRef,
    RuntimeEventSummary,
    RuntimeFactsProjection,
    SourceBindingProjection,
    SubjectRef,
    SubjectRuntimeProjection,
    WorkspaceRef
  }

  alias Ecto.Adapters.SQL.Sandbox
  alias ExtravaganzaCore.MixProject, as: CoreMixProject

  alias Extravaganza.{
    CodingOpsTemplates,
    Config,
    DefaultAuthoringBundle,
    HeadlessSameRunSmoke,
    PolicyPresets,
    ProductBootstrap,
    ProductHost,
    ProductInstallTemplate,
    ProductPack,
    Queries,
    Reviews,
    RunProfiles.DefaultCodexProfile,
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

  defmodule FakeRuntimeProjectionBackend do
    def get_runtime_projection(_context, %SubjectRef{} = subject_ref, _opts) do
      {:ok, runtime_projection(subject_ref)}
    end

    defp runtime_projection(%SubjectRef{} = subject_ref) do
      {:ok, source_binding} =
        SourceBindingProjection.new(%{
          binding_ref: "linear_primary",
          source_ref: "source://linear/discovered-task",
          source_kind: "linear",
          external_system: "linear",
          source_state: "In Review",
          source_url: "https://linear.app/example/issue/ENG-900",
          workpad_refs: ["source-workpad://linear/discovered-task"]
        })

      {:ok, workspace_ref} =
        WorkspaceRef.new(%{
          id: "workspace://extravaganza/discovered-task",
          tenant_id: "tenant-runtime-preview"
        })

      {:ok, execution_ref} =
        ExecutionRef.new(%{
          id: "execution://extravaganza/discovered-task",
          subject_ref: subject_ref,
          recipe_ref: "coding_operations",
          dispatch_state: "terminal_success"
        })

      {:ok, execution_state} =
        ExecutionStateProjection.new(%{
          execution_ref: execution_ref,
          lifecycle_state: "awaiting_review",
          dispatch_state: "terminal_success"
        })

      {:ok, lower_receipt} =
        LowerReceiptSummary.new(%{
          receipt_ref: "receipt://terminal-success",
          receipt_state: "succeeded",
          lower_receipt_ref: "lower_receipt://terminal-success",
          run_ref: "lower-run://terminal-success",
          attempt_ref: "lower-attempt://terminal-success",
          execution_ref: execution_ref
        })

      {:ok, runtime_event} =
        RuntimeEventSummary.new(%{
          event_kind: "codex.session.completed",
          count: 1,
          latest_event_ref: "runtime-event://terminal-success"
        })

      {:ok, runtime} =
        RuntimeFactsProjection.new(%{
          token_totals: %{"input" => 1200, "output" => 400},
          rate_limit: %{"status" => "ok"},
          events: [runtime_event]
        })

      evidence =
        [
          evidence!("github_pr", "evidence://github-pr", "github-pr://dynamic-result"),
          evidence!(
            "codex_session",
            "evidence://codex-session",
            "codex-session://dynamic-result"
          ),
          evidence!(
            "source_workpad",
            "evidence://source-workpad",
            "source-workpad://linear/discovered-task"
          )
        ]

      {:ok, decision_ref} =
        DecisionRef.new(%{
          id: "decision://operator-review",
          decision_kind: "operator_review",
          subject_ref: subject_ref
        })

      {:ok, review} =
        ReviewProjection.new(%{
          status: "pending",
          pending_decision_refs: [decision_ref]
        })

      {:ok, projection} =
        SubjectRuntimeProjection.new(%{
          subject_ref: subject_ref,
          lifecycle_state: "awaiting_review",
          source_bindings: [source_binding],
          workspace_ref: workspace_ref,
          execution_state: execution_state,
          lower_receipts: [lower_receipt],
          runtime: runtime,
          evidence: evidence,
          review: review,
          updated_at: ~U[2026-04-25 12:00:00Z],
          schema_ref: "app_kit.subject_runtime_projection.v1",
          schema_version: 1
        })

      projection
    end

    defp evidence!(kind, evidence_ref, content_ref) do
      {:ok, evidence} =
        EvidenceProjection.new(%{
          evidence_ref: evidence_ref,
          evidence_kind: kind,
          status: "present",
          content_ref: content_ref
        })

      evidence
    end
  end

  setup do
    base_config = Application.fetch_env!(:extravaganza_core, Config)

    test_suffix = "#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive])}"
    version_suffix = String.replace(test_suffix, "_", ".")
    pack_version = "1.0.0-test.#{version_suffix}"

    Application.put_env(
      :extravaganza_core,
      Config,
      Keyword.merge(base_config,
        pack_version: pack_version
      )
    )

    repo_specs = [
      {RuntimeStack.ops_domain_repo(), [shared: false]},
      {ConfigRegistryRepo, [shared: true]},
      {AuditRepo, [shared: false]},
      {ExecutionRepo, [shared: false]},
      {DecisionsRepo, [shared: false]},
      {EvidenceRepo, [shared: false]}
    ]

    repo_specs
    |> Enum.map(&elem(&1, 0))
    |> ensure_repos_started()

    owners = start_sandbox_owners(repo_specs)

    [_ops_owner, config_owner | _rest] = owners
    allow_registry_process(config_owner)

    tenant_id = "extravaganza-test-#{Ecto.UUID.generate()}"

    on_exit(fn ->
      Application.put_env(:extravaganza_core, Config, base_config)
      Enum.each(owners, &Sandbox.stop_owner/1)
    end)

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

    non_runtime_mezzanine_overrides = [
      :mezzanine_pack_compiler,
      :mezzanine_config_registry,
      :mezzanine_execution_engine,
      :mezzanine_integration_bridge
    ]

    assert Enum.any?(deps, fn
             {:mezzanine_pack_model, _opts} -> true
             {:mezzanine_pack_model, _req, _opts} -> true
             _other -> false
           end)

    refute Enum.any?(deps, fn
             {app, opts} ->
               app in non_runtime_mezzanine_overrides && Keyword.get(opts, :runtime, true)

             {app, _req, opts} ->
               app in non_runtime_mezzanine_overrides && Keyword.get(opts, :runtime, true)

             _other ->
               false
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

  test "product pack declares Linear source bindings, source publishing, and runtime policy" do
    config = Config.load()

    assert {:ok, compiled_pack} =
             config
             |> ProductPack.manifest()
             |> Compiler.compile()

    source_binding = compiled_pack.source_bindings_by_ref["linear_primary"]

    assert source_binding.provider == "linear"
    assert source_binding.connection_ref == "linear_primary"
    assert source_binding.source_kind == "linear"
    assert source_binding.subject_kind == config.work_class_kind
    assert source_binding.state_mapping["awaiting_review"] == ["In Review"]
    assert source_binding.source_write_policy.claim_state == "In Progress"

    source_publisher = compiled_pack.source_publishers_by_ref["linear_workpad_review"]

    assert source_publisher.source_binding_ref == "linear_primary"
    assert source_publisher.trigger == {:subject_entered_state, "awaiting_review"}
    assert source_publisher.operation == :update_comment
    assert source_publisher.template_ref == "operator_review_workpad"

    recipe = compiled_pack.recipes_by_ref[ProductPack.execution_recipe_ref(config)]

    assert recipe.workspace_policy.root_ref == "extravaganza_workspaces"
    assert recipe.sandbox_policy_ref == "standard_coding_ops"
    assert recipe.prompt_refs == ["coding_agent_system"]

    assert compiled_pack.context_sources_by_ref["workspace_memory"].binding_key ==
             "shared_memory"

    assert compiled_pack.context_sources_by_ref["workspace_memory"].required? == false

    assert recipe.dynamic_tool_manifest.tools == [
             "linear.comments.update",
             "linear.graphql.execute",
             "github.pr.create",
             "github.pr.fetch",
             "github.pr.list",
             "github.pr.reviews.list",
             "github.pr.review_comments.list"
           ]

    assert recipe.hook_stages == [:prepare_workspace, :after_turn]
    assert recipe.max_turns == 12
    assert recipe.stall_timeout_ms == 300_000
    assert ProductPack.profile_slots(config).runtime_profile_ref == :codex_session
    assert ProductPack.profile_slots(config).memory_profile_ref == :none

    review_gate = compiled_pack.decision_specs_by_kind["operator_review"]

    assert review_gate.required_evidence_kinds == [
             "codex_session",
             "github_pr",
             "source_workpad"
           ]

    assert review_gate.allowed_decisions == [:accept, :expired, :reject, :waive]

    assert compiled_pack.evidence_specs_by_kind["github_pr"].collector_ref == "github_pr_ref"

    assert compiled_pack.evidence_specs_by_kind["codex_session"].collector_ref ==
             "codex_session_ref"

    assert compiled_pack.evidence_specs_by_kind["source_workpad"].collector_ref ==
             "linear_workpad_ref"

    assert compiled_pack.operator_actions_by_kind["pause"].effect == :pause_execution
    assert compiled_pack.operator_actions_by_kind["resume"].effect == :resume_execution

    assert compiled_pack.operator_actions_by_kind["cancel"].effect ==
             :cancel_active_execution

    assert compiled_pack.operator_actions_by_kind["rework"].effect ==
             {:advance_lifecycle, "retry_submission"}

    install_template = ProductInstallTemplate.default(config)

    assert get_in(install_template.default_bindings, [
             "source_bindings",
             "linear_primary",
             "provider"
           ]) == "linear"

    assert get_in(install_template.default_bindings, [
             "source_bindings",
             "linear_primary",
             "connection_ref"
           ]) == "linear_primary"

    assert get_in(install_template.default_bindings, [
             "execution_bindings",
             ProductPack.execution_binding_key(config),
             "runtime_profile_ref"
           ]) == DefaultCodexProfile.profile_ref()

    [companion] = ProductInstallTemplate.companion_connectors(config)

    assert companion["connector_ref"] ==
             "connector://#{config.tenant_id}/extravaganza-linear-safe-read"

    assert companion["tenant_ref"] == "tenant://#{config.tenant_id}"
    assert companion["contract_version"] == "connector-sdk.v1"
    assert companion["persistence_profile"] == "memory-default"
    assert companion["admission_policy"] == "explicit_app_config_only"
    assert companion["capability_ids"] == ["extravaganza_linear_safe_read.issue.fetch"]
    assert companion["auth_profiles"] == ["default_manual_secret"]
    assert companion["scopes"] == ["linear:read"]
    refute Map.has_key?(companion, "provider_account_id")
    refute Map.has_key?(companion, "secret_metadata")

    assert install_template.metadata["companion_connectors"] == [companion]
  end

  test "unknown ProductPack names reject before refs are built" do
    assert_product_pack_rejects(work_class_kind: unique_product_pack_name("subject"))
    assert_product_pack_rejects(linear_source_kind: unique_product_pack_name("source"))
    assert_product_pack_rejects(work_class_name: unique_product_pack_name("recipe"))
    assert_product_pack_rejects(placement_profile_id: unique_product_pack_name("placement"))

    assert_product_install_template_rejects(
      [linear_source_kind: unique_product_pack_name("source-binding")],
      :source_binding_ref
    )

    assert_product_install_template_rejects(
      [placement_profile_id: unique_product_pack_name("placement-binding")],
      :placement_profile_id
    )

    assert {:ok, _compiled_pack} =
             Config.load()
             |> ProductPack.manifest()
             |> Compiler.compile()
  end

  test "default coding ops policy uses canonical provider capability IDs" do
    runtime_config = PolicyPresets.DefaultCodingOps.runtime_config()

    assert runtime_config["run"] == %{
             "profile" => DefaultCodexProfile.profile_key(),
             "runtime_class" => DefaultCodexProfile.runtime_class(),
             "lower_runtime_kind" => DefaultCodexProfile.lower_runtime_kind(),
             "capability" => DefaultCodexProfile.capability_id(),
             "target" => DefaultCodexProfile.target_ref()
           }

    assert runtime_config["memory"] == %{
             "enabled" => false,
             "memory_profile_ref" => "none",
             "context_profile_ref" => "outer_brain_optional_context_v1",
             "required_for_run" => false,
             "query_class" => "semantic",
             "max_results" => 3,
             "redaction_policy_ref" => "redaction://extravaganza/memory/hash-only"
           }

    capability_ids =
      runtime_config["capability_grants"]
      |> Enum.map(&Map.fetch!(&1, "capability_id"))

    assert capability_ids == [
             "codex.session.turn",
             "linear.issues.list",
             "linear.issues.retrieve",
             "linear.issues.update",
             "linear.comments.create",
             "linear.comments.update",
             "linear.users.get_self",
             "linear.workflow_states.list",
             "linear.graphql.execute",
             "github.pr.create",
             "github.pr.fetch",
             "github.pr.list",
             "github.pr.update",
             "github.pr.reviews.list",
             "github.pr.review_comments.list",
             "github.pr.review.create",
             "github.pr.review_comment.create",
             "github.commit.statuses.get_combined",
             "github.check_runs.list_for_ref"
           ]

    assert :ok = Workflows.validate_runtime_profile_compatibility(Config.load(), runtime_config)
  end

  test "runtime compatibility fails closed before run start when product and policy diverge" do
    runtime_config =
      PolicyPresets.DefaultCodingOps.runtime_config()
      |> put_in(["run", "lower_runtime_kind"], "direct_connector")

    assert {:error, {:incompatible_product_runtime_profile, details}} =
             Workflows.validate_runtime_profile_compatibility(Config.load(), runtime_config)

    assert details.field == :lower_runtime_kind
    assert details.actual == "direct_connector"

    assert details.expected_selection["lower_runtime_kind"] ==
             DefaultCodexProfile.lower_runtime_kind()
  end

  test "product runtime code does not import lower governance or execution internals" do
    forbidden_fragments = [
      "Jido.Integration.",
      "Citadel.",
      "ExecutionPlane.",
      "Mezzanine.WorkflowRuntime",
      "Mezzanine.IntegrationBridge",
      "Mezzanine.Citadel"
    ]

    for source_file <- product_runtime_source_files(),
        source = File.read!(source_file),
        forbidden_fragment <- forbidden_fragments do
      refute String.contains?(source, forbidden_fragment),
             "#{source_file} imports lower/internal boundary #{forbidden_fragment}"
    end
  end

  test "product prompt and source workpad preview render from app kit runtime projection", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    workflow_body = PolicyPresets.default_coding_ops().body
    normalized_workflow_body = workflow_body |> String.split() |> Enum.join(" ")

    assert String.contains?(workflow_body, CodingOpsTemplates.prompt_ref())

    assert String.contains?(
             normalized_workflow_body,
             PolicyPresets.DefaultCodingOps.prompt_artifact_ref().prompt_id
           )

    assert String.contains?(
             normalized_workflow_body,
             PolicyPresets.DefaultCodingOps.guard_chain_ref().guard_chain_ref
           )

    assert String.contains?(
             normalized_workflow_body,
             PolicyPresets.DefaultCodingOps.budget_policy_ref()
           )

    refute String.contains?(workflow_body, "provider refs must come from")
    refute String.contains?(workflow_body, "TODO")

    assert {:ok, preview} =
             ProductHost.source_publication_preview(
               "subject-runtime-preview",
               tenant_id: tenant_id,
               pack_version: pack_version,
               work_query_backend: FakeRuntimeProjectionBackend
             )

    assert preview.publish_ref == "linear_workpad_review"
    assert preview.template_ref == CodingOpsTemplates.workpad_template_ref()
    assert preview.operation == :update_comment
    assert preview.source_binding_ref == "linear_primary"
    assert preview.lifecycle_state == "awaiting_review"
    assert preview.lower_receipt_refs == ["receipt://terminal-success"]

    assert preview.evidence_refs == [
             "evidence://github-pr",
             "evidence://codex-session",
             "evidence://source-workpad"
           ]

    assert preview.pending_decision_refs == ["decision://operator-review"]
    assert String.contains?(preview.body, "Operator Review Workpad")
    assert String.contains?(preview.body, "source://linear/discovered-task")
    assert String.contains?(preview.body, "lower_receipt://terminal-success")
    assert String.contains?(preview.body, "github_pr")
    assert String.contains?(preview.body, "codex.session.completed=1")
    refute String.contains?(preview.body, "github_issue_number")
    refute String.contains?(preview.body, "linear_issue_id")
  end

  test "default authoring bundle rejects workflow-body runtime policy before activation", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    config = Config.load(tenant_id: tenant_id, pack_version: pack_version)

    legacy_workflow_body = """
    ---
    retry:
      strategy: exponential
      max_attempts: 4
    ---
    #{CodingOpsTemplates.system_prompt()}
    """

    assert {:error, {:runtime_policy_conflict, details}} =
             DefaultAuthoringBundle.build(config,
               installation_id: "default",
               workflow_body: legacy_workflow_body
             )

    assert details.field == :retry
    assert details.final_owner == :authoring_bundle
    assert details.product_pack.retry.max_attempts == 2
    assert details.workflow_body.retry.max_attempts == 4
  end

  test "default coding ops keeps prompt body separate from runtime config" do
    preset = PolicyPresets.default_coding_ops()

    assert preset.policy_kind == :structured_config
    refute String.contains?(preset.body, "---")
    refute String.contains?(preset.body, "AITrace")
    refute String.contains?(preset.body, "Provider identity source")
    assert String.contains?(preset.body, CodingOpsTemplates.prompt_ref())

    assert preset.metadata["prompt_author_request"].prompt_id ==
             "prompt://extravaganza/coding_agent_system"

    assert preset.metadata["guard_chain_ref"].guard_chain_ref ==
             "guard-chain://extravaganza/coding_ops/default"

    assert preset.metadata["budget_policy"].budget_policy_ref ==
             "budget-policy://extravaganza/coding_ops/default"

    assert preset.metadata["budget_policy"].default_exhaustion_behavior == "fail_closed"

    config = preset.metadata["runtime_policy_config"]
    assert config["retry"]["strategy"] == "linear"
    assert config["retry"]["max_attempts"] == 2
    assert config["review"]["required"] == true
    assert config["budget"]["fail_closed"] == true
  end

  test "prompt context rendering is strict for known issue and attempt variables" do
    template = """
    Issue: {{ issue.identifier }} {{ issue.title }}
    Labels: {{ issue.labels | join: ", " }}
    Attempt: {{ attempt | default: "first" }}
    Runtime: {{ runtime_profile_ref }}
    """

    assert {:ok, rendered} =
             CodingOpsTemplates.render_prompt_template(template, %{
               "issue" => %{
                 "identifier" => "ENG-900",
                 "title" => "Strict prompt context",
                 "labels" => ["agent", "governance"]
               },
               "attempt" => nil,
               "runtime_profile_ref" => DefaultCodexProfile.profile_ref()
             })

    assert String.contains?(rendered, "Issue: ENG-900 Strict prompt context")
    assert String.contains?(rendered, "Labels: agent, governance")
    assert String.contains?(rendered, "Attempt: first")
    assert String.contains?(rendered, "Runtime: #{DefaultCodexProfile.profile_ref()}")
  end

  test "prompt context compiler rejects unknown variables and filters" do
    assert {:error,
            {:template_render_error, %{reason: :unknown_variable, variable: "issue.secret"}}} =
             CodingOpsTemplates.compile_prompt_template("{{ issue.secret }}")

    assert {:error, {:template_render_error, %{reason: :unknown_filter, filter: "upcase"}}} =
             CodingOpsTemplates.compile_prompt_template("{{ issue.title | upcase }}")

    assert {:error, {:template_parse_error, %{reason: :unbalanced_interpolation}}} =
             CodingOpsTemplates.compile_prompt_template("{{ issue.title")
  end

  test "bootstrap imports the default authoring bundle and activates runtime policy revision", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, profile} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert profile.authoring_result.message == "Authoring bundle imported"
    assert profile.installation_ref.status == :active
    assert profile.bundle.bundle_id == "extravaganza_coding_ops-default-#{pack_version}"
    assert String.contains?(profile.bundle.checksum, "sha256:")

    assert {:ok, compiled_pack} =
             Mezzanine.Pack.Registry.get_compiled_pack(
               profile.installation_ref.id,
               profile.installation_ref.compiled_pack_revision
             )

    recipe = compiled_pack.recipes_by_ref[ProductPack.execution_recipe_ref(profile.config)]

    assert recipe.retry_config.max_attempts == 2
    assert recipe.retry_config.backoff == :linear
    assert recipe.sandbox_policy_ref == "standard_coding_ops"
    assert recipe.prompt_refs == [CodingOpsTemplates.prompt_ref()]
  end

  test "cold bootstrap imports authoring bundle then returns app kit installation state", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    assert {:ok, profile} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert profile.bootstrap_install_result == nil
    assert profile.install_result.status in [:created, :updated, :reused]
    assert profile.installation_ref.status == :active
    assert profile.installation_ref.pack_slug == ProductPack.pack_slug(profile.config)
    assert profile.installation_ref.pack_version == pack_version

    execution_binding =
      get_in(profile.install_result.metadata, [
        :installation,
        :bindings,
        "execution_bindings",
        ProductPack.execution_binding_key(profile.config)
      ])

    assert execution_binding["runtime_profile_ref"] == DefaultCodexProfile.profile_ref()

    assert execution_binding["execution_params"]["timeout_ms"] ==
             profile.config.execution_timeout_ms
  end

  test "product runtime does not hardcode app kit bridge implementations" do
    refute File.exists?(Path.expand("../lib/extravaganza/app_kit_backends.ex", __DIR__))

    [
      Path.expand("../lib/extravaganza/application.ex", __DIR__),
      Path.expand("../lib/extravaganza/product_bootstrap.ex", __DIR__),
      Path.expand("../lib/extravaganza/product_surface.ex", __DIR__)
    ]
    |> Enum.each(fn path ->
      contents = File.read!(path)

      refute String.contains?(contents, "AppKit.Bridges.MezzanineBridge"),
             "#{path} still hardcodes the AppKit mezzanine bridge"

      refute String.contains?(contents, "MezzanineConfigRegistry"),
             "#{path} bypasses AppKit for ConfigRegistry writes"

      refute String.contains?(contents, "AppKitBackends.ensure_configured"),
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
             [
               "execution_bindings",
               ProductPack.execution_binding_key(Config.load()),
               "execution_params",
               "timeout_ms"
             ]
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
      url: "https://linear.app/example/issue/ENG-101",
      blockers: [
        %{
          id: "rel-blocks-101",
          type: "blocks",
          direction: "inbound",
          issue: %{
            id: "lin-issue-099",
            identifier: "ENG-099",
            title: "Restore queue credentials",
            url: "https://linear.app/example/issue/ENG-099",
            state: %{id: "state-started", name: "In Progress", type: "started"}
          }
        }
      ]
    }

    assert {:ok, first_subject} =
             LinearIssueFixture.ingest_issue(
               issue,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert first_subject.payload.external_ref == "linear://#{tenant_id}/issue/ENG-101"
    assert first_subject.title == "Investigate operator queue"
    assert [%{blocker_kind: "source_blocked"}] = first_subject.blocking_conditions
    assert first_subject.next_step_preview.status == "blocked"

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
    assert second_subject.payload.external_ref == "linear://#{tenant_id}/issue/ENG-101"
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

    assert result.payload.recipe_ref == ProductPack.execution_recipe_ref([])

    assert {:ok, status} = Queries.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert status.work_object_id == result.payload.work_object_id
    assert is_list(status.timeline)
    assert is_map(status.gate_status)
  end

  test "product-local start_run sends complete run request metadata for governed lower dispatch",
       %{
         tenant_id: tenant_id,
         pack_version: pack_version
       } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-207",
                 title: "Carry governed run metadata",
                 description: "RunRequest should carry enough refs for the lower envelope",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-207"},
                 normalized_payload: %{"issue_id" => "ENG-207"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    metadata = result.payload.run_request_metadata

    assert result.payload.recipe_ref == ProductPack.execution_recipe_ref([])

    assert result.payload.params["runtime_policy_config"]["run"]["capability"] ==
             "codex.session.turn"

    assert metadata["idempotency_key"] == result.payload.run_ref.metadata.idempotency_key
    assert metadata["pack_revision"] == result.payload.run_ref.metadata.pack_revision
    assert metadata["runtime_profile_ref"] == "codex_session"
    assert metadata["runtime_profile_kind"] == "temporal_local"
    assert metadata["runtime_profile_revision"] == 1
    assert metadata["lower_runtime_kind"] == "codex_session"
    assert metadata["requested_action_ids"] == ["codex.session.turn"]
    assert "codex.session.turn" in metadata["requested_capability_ids"]
    assert "linear.comments.update" in metadata["requested_capability_ids"]
    assert metadata["source_binding_refs"] == ["linear_primary"]
    assert "source_binding://linear_primary" in metadata["resource_scope_refs"]

    assert metadata["workspace_policy_ref"] ==
             "workspace-policy://extravaganza_coding_ops/coding_operations"

    assert metadata["live_provider_allowed"] == false
    assert metadata["evidence_profile_ref"] == "github_pr_plus_workpad"
    assert metadata["memory_profile_ref"] == "none"
    assert metadata["context_profile_ref"] == "outer_brain_optional_context_v1"
    assert metadata["memory_context_required"] == false
    assert metadata["memory_context_source_refs"] == ["workspace_memory"]
    assert metadata["memory_context_binding_keys"] == ["shared_memory"]
    assert metadata["redaction_profile_ref"] == "redaction://extravaganza/default"
    assert metadata["prompt_context_recipe_refs"] == [CodingOpsTemplates.prompt_ref()]
    assert String.starts_with?(result.payload.workflow_start_ref, "workflow-start-outbox://")
    assert String.starts_with?(result.payload.workflow_start_outbox_id, "workflow-start:")
    assert result.payload.workflow_dispatch_state == "queued"
    assert result.payload.workflow_start_ref == result.payload.run_ref.metadata.workflow_start_ref
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
               %{id: pending_review.decision_ref.id},
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
        occurred_at: DateTime.add(DateTime.utc_now(), 1, :second),
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

  test "product-owned local acceptance covers the full headless run and review path", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, start_result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-950",
                 title: "Product-owned local acceptance",
                 description: "Prove the local product path from Extravaganza",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-950"},
                 normalized_payload: %{"issue_id" => "ENG-950"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert start_result.surface == :work_control
    assert start_result.state == :waiting_review

    assert String.starts_with?(
             start_result.payload.workflow_start_ref,
             "workflow-start-outbox://"
           )

    assert start_result.payload.workflow_dispatch_state == "queued"

    metadata = start_result.payload.run_request_metadata

    assert metadata["runtime_profile_ref"] == "codex_session"
    assert metadata["runtime_profile_kind"] == "temporal_local"
    assert metadata["lower_runtime_kind"] == "codex_session"
    assert metadata["requested_action_ids"] == ["codex.session.turn"]
    assert "codex.session.turn" in metadata["requested_capability_ids"]
    assert "linear.comments.update" in metadata["requested_capability_ids"]
    assert "source_binding://linear_primary" in metadata["resource_scope_refs"]
    assert metadata["live_provider_allowed"] == false

    assert {:ok, status} =
             ProductHost.run_status(start_result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert status.work_object_id == start_result.payload.work_object_id
    assert is_list(status.timeline)

    assert {:ok, queue} =
             ProductHost.operator_queue(%{}, tenant_id: tenant_id, pack_version: pack_version)

    assert Enum.any?(
             queue.page.entries,
             &(&1.subject_ref.id == start_result.payload.work_object_id)
           )

    assert {:ok, reviews_page} =
             ProductHost.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    pending_review =
      Enum.find(
        reviews_page.page.entries,
        &(&1.subject_ref.id == start_result.payload.work_object_id)
      ) || flunk("expected pending review for #{start_result.payload.work_object_id}")

    assert {:ok, review_result} =
             ProductHost.record_review_decision(
               review_identity(pending_review),
               %{decision: :accept, reason: "accepted by product-owned local acceptance"},
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert review_result.status == :completed
    assert review_result.action_ref.action_kind in ["review_accept", "review_run"]

    assert {:ok, after_reviews_page} =
             ProductHost.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    refute Enum.any?(
             after_reviews_page.page.entries,
             &(&1.decision_ref.id == pending_review.decision_ref.id)
           )

    assert {:ok, preview} =
             ProductHost.source_publication_preview(
               start_result.payload.work_object_id,
               tenant_id: tenant_id,
               pack_version: pack_version,
               work_query_backend: FakeRuntimeProjectionBackend
             )

    assert preview.publish_ref == "linear_workpad_review"
    assert preview.operation == :update_comment
    assert preview.source_binding_ref == "linear_primary"
    assert preview.lower_receipt_refs == ["receipt://terminal-success"]

    assert preview.evidence_refs == [
             "evidence://github-pr",
             "evidence://codex-session",
             "evidence://source-workpad"
           ]

    assert String.contains?(preview.body, "Operator Review Workpad")
    assert String.contains?(preview.body, "github_pr")
    assert String.contains?(preview.body, "codex.session.completed=1")
  end

  test "same-run deterministic smoke keeps all public readbacks on one subject and run", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    assert {:ok, smoke} =
             ProductHost.same_run_smoke(tenant_id: tenant_id, pack_version: pack_version)

    proof = Map.fetch!(smoke, "proof")

    assert proof["proof_class"] == "product_same_run_deterministic"
    assert proof["all_readbacks_share_refs"] == true
    assert is_binary(proof["subject_ref"])
    assert is_binary(proof["run_ref"])
    assert is_binary(proof["workflow_ref"])

    readback_names = Enum.map(proof["readbacks"], & &1["name"])
    proof_steps = Map.fetch!(proof, "steps")

    assert "workflow_start_outbox_queued" in proof_steps
    assert "current_execution_row_created" in proof_steps
    assert "mezzanine_runtime_projection_projected" in proof_steps
    assert "deterministic_authority_projected" in proof_steps
    assert "deterministic_lower_projected" in proof_steps
    assert "deterministic_receipt_projected" in proof_steps
    refute "pending_lower_receipt_projected" in proof_steps
    refute String.contains?(proof["lower_receipt_ref"], "/pending/")

    assert readback_names == [
             "state",
             "queue",
             "subject",
             "run",
             "evidence",
             "events",
             "reviews",
             "review_decision",
             "source_preview",
             "source_publication",
             "refresh",
             "control",
             "read_lease",
             "stream_attach_lease"
           ]

    assert :ok = HeadlessSameRunSmoke.assert_same_run!(proof)

    mismatched =
      update_in(proof, ["readbacks", Access.at!(0), "run_ref"], fn _ -> "run://mismatch" end)

    assert_raise ArgumentError, ~r/same-run readback refs diverged: state/, fn ->
      HeadlessSameRunSmoke.assert_same_run!(mismatched)
    end
  end

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        activate_registration!(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        activate_registration!(registration)
    end
  end

  defp activate_registration!(%PackRegistration{} = registration) do
    deprecate_active_subject_kind_overlaps!(registration)
    assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
  end

  defp deprecate_active_subject_kind_overlaps!(%PackRegistration{} = registration) do
    subject_kinds = MapSet.new(registration.canonical_subject_kinds)
    assert {:ok, active_registrations} = PackRegistration.list_active()

    active_registrations
    |> Enum.reject(&(&1.id == registration.id))
    |> Enum.filter(fn active_registration ->
      active_subject_kinds = MapSet.new(active_registration.canonical_subject_kinds)
      not MapSet.disjoint?(subject_kinds, active_subject_kinds)
    end)
    |> Enum.each(fn active_registration ->
      assert {:ok, %PackRegistration{status: :deprecated}} =
               PackRegistration.deprecate(active_registration)
    end)
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

  defp ensure_repos_started(repos) do
    Enum.each(repos, fn repo ->
      case repo.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end)
  end

  defp start_sandbox_owners(repo_specs) do
    do_start_sandbox_owners(repo_specs, [])
  end

  defp do_start_sandbox_owners([], owners), do: Enum.reverse(owners)

  defp do_start_sandbox_owners([{repo, opts} | rest], owners) do
    owner = Sandbox.start_owner!(repo, opts)
    do_start_sandbox_owners(rest, [owner | owners])
  rescue
    exception ->
      Enum.each(owners, &Sandbox.stop_owner/1)
      reraise exception, __STACKTRACE__
  end

  defp assert_product_pack_rejects(overrides) do
    ProductPack.manifest(overrides)
    flunk("ProductPack accepted invalid config #{inspect(overrides)}")
  rescue
    ArgumentError -> :ok
  end

  defp assert_product_install_template_rejects(overrides, field) do
    overrides
    |> Config.load()
    |> ProductInstallTemplate.default()

    flunk("Product install template accepted invalid config #{inspect(overrides)}")
  rescue
    error in [ArgumentError] ->
      assert String.contains?(Exception.message(error), "unknown ProductPack #{field}")
  end

  defp product_runtime_source_files do
    [
      Path.expand("../lib/**/*.ex", __DIR__),
      Path.expand("../../extravaganza_web/lib/**/*.ex", __DIR__)
    ]
    |> Enum.flat_map(&Path.wildcard/1)
  end

  defp unique_product_pack_name(prefix),
    do: prefix <> "_" <> Integer.to_string(System.unique_integer([:positive]))
end
