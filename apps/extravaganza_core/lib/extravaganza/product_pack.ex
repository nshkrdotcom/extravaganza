defmodule Extravaganza.ProductPack do
  @moduledoc """
  Product-owned pack definition for the default Extravaganza coding workflow.
  """

  @behaviour Mezzanine.Pack

  alias Extravaganza.Config

  alias Mezzanine.Pack.{
    DecisionSpec,
    EvidenceSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    OperatorActionSpec,
    ProjectionSpec,
    SourceBindingSpec,
    SourceKindSpec,
    SourcePublishSpec,
    SubjectKindSpec
  }

  @subject_kinds %{"coding_task" => :coding_task}
  @source_kinds %{"linear" => :linear}
  @source_binding_refs %{"linear" => :linear_primary}
  @recipe_refs %{"coding_operations" => :coding_operations}
  @placement_refs %{"local_default" => :local_default}

  @impl true
  def manifest, do: manifest(Config.load())

  @spec manifest(Config.t() | keyword() | map()) :: Manifest.t()
  def manifest(%Config{} = config) do
    subject_kind = subject_kind(config)
    source_kind = source_kind(config)
    source_binding_ref = source_binding_ref(config)
    recipe_ref = execution_recipe_ref_atom(config)

    %Manifest{
      pack_slug: pack_slug(config),
      version: pack_version(config),
      description: "#{config.program_name} product pack",
      profile_slots: profile_slots(config),
      subject_kind_specs: [
        %SubjectKindSpec{
          name: subject_kind,
          description: "One Extravaganza coding task subject",
          payload_schema: %{identifier: :string, title: :string, source_kind: :string}
        }
      ],
      source_kind_specs: [
        %SourceKindSpec{
          name: source_kind,
          subject_kind: subject_kind,
          description: "Linear-backed coding task intake"
        }
      ],
      source_binding_specs: [
        %SourceBindingSpec{
          binding_ref: source_binding_ref,
          source_kind: source_kind,
          subject_kind: subject_kind,
          provider: :linear,
          connection_ref: :linear_primary,
          state_mapping: %{
            submitted: ["Todo", "Backlog"],
            awaiting_review: ["In Review"],
            retry_submission: ["Todo"],
            completed: ["Done", "Completed"],
            rejected: ["Canceled", "Cancelled", "Duplicate"],
            expired: ["Canceled", "Cancelled"]
          },
          candidate_filters: %{source_kind: config.linear_source_kind},
          cursor_policy: %{poll_every_ms: 60_000},
          source_write_policy: %{workpad: :update_existing, claim_state: "In Progress"}
        }
      ],
      source_publish_specs: [
        %SourcePublishSpec{
          publish_ref: :linear_workpad_review,
          source_binding_ref: source_binding_ref,
          trigger: {:subject_entered_state, :awaiting_review},
          operation: :update_comment,
          template_ref: :operator_review_workpad,
          idempotency_scope: :subject
        }
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: subject_kind,
          initial_state: :submitted,
          terminal_states: [:completed, :rejected, :expired],
          transitions: [
            %{
              from: :submitted,
              to: :awaiting_review,
              trigger: {:execution_completed, recipe_ref}
            },
            %{
              from: :submitted,
              to: :retry_submission,
              trigger: {:execution_failed, recipe_ref}
            },
            %{
              from: :retry_submission,
              to: :submitted,
              trigger: :auto
            },
            %{
              from: :awaiting_review,
              to: :completed,
              trigger: {:decision_made, :operator_review, :accept}
            },
            %{
              from: :awaiting_review,
              to: :completed,
              trigger: {:decision_made, :operator_review, :waive}
            },
            %{
              from: :awaiting_review,
              to: :rejected,
              trigger: {:decision_made, :operator_review, :reject}
            },
            %{
              from: :awaiting_review,
              to: :expired,
              trigger: {:decision_made, :operator_review, :expired}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: recipe_ref,
          description: "Drive the default Extravaganza coding workflow",
          runtime_class: :workflow,
          placement_ref: placement_ref(config),
          retry_config: %{
            max_attempts: 2,
            backoff: :linear,
            retry_on: [:transient_failure, :timeout]
          },
          workspace_policy: %{
            strategy: :per_subject,
            reuse: true,
            cleanup: :on_terminal,
            root_ref: :extravaganza_workspaces
          },
          sandbox_policy_ref: :standard_coding_ops,
          prompt_refs: [:coding_agent_system],
          dynamic_tool_manifest: %{tools: ["linear.comment.update", "github.pr.create"]},
          hook_stages: [:prepare_workspace, :after_turn],
          max_turns: 12,
          stall_timeout_ms: 300_000,
          execution_params: %{timeout_ms: config.execution_timeout_ms},
          applicable_to: [subject_kind]
        }
      ],
      decision_specs: [
        %DecisionSpec{
          decision_kind: :operator_review,
          description: "Operator review gate for Extravaganza coding tasks",
          trigger: {:after_execution_completed, recipe_ref},
          required_evidence_kinds: [:github_pr, :codex_session, :source_workpad],
          authorized_actors: [:operator],
          allowed_decisions: [:accept, :reject, :waive, :expired],
          required_within_hours: 72
        }
      ],
      evidence_specs: [
        %EvidenceSpec{
          evidence_kind: :github_pr,
          description: "GitHub pull request or PR-attempt evidence for the coding task",
          collector_ref: :github_pr_ref,
          collection_strategy: :automatic,
          collected_on: {:execution_completed, recipe_ref},
          schema: %{url: :string, number: :integer, state: :string}
        },
        %EvidenceSpec{
          evidence_kind: :codex_session,
          description: "Codex session, transcript, and token/rate evidence",
          collector_ref: :codex_session_ref,
          collection_strategy: :automatic,
          collected_on: {:execution_completed, recipe_ref},
          schema: %{session_id: :string, transcript_ref: :string}
        },
        %EvidenceSpec{
          evidence_kind: :source_workpad,
          description: "Linear workpad/progress comment evidence",
          collector_ref: :linear_workpad_ref,
          collection_strategy: :automatic,
          collected_on: {:subject_entered_state, :awaiting_review},
          schema: %{comment_id: :string, url: :string}
        }
      ],
      operator_action_specs: [
        %OperatorActionSpec{
          action_kind: :pause_execution,
          description: "Pause the active coding execution for operator review",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :pause_execution
        },
        %OperatorActionSpec{
          action_kind: :resume_execution,
          description: "Resume a paused coding execution",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :resume_execution
        },
        %OperatorActionSpec{
          action_kind: :cancel_execution,
          description: "Cancel the active coding execution",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :cancel_active_execution
        },
        %OperatorActionSpec{
          action_kind: :request_rework,
          description: "Return the coding task to retry submission for rework",
          applicable_states: [:awaiting_review],
          authorized_roles: [:operator],
          effect: {:advance_lifecycle, :retry_submission}
        }
      ],
      projection_specs: [
        %ProjectionSpec{
          name: :operator_queue,
          description: "Operator queue for pending coding tasks",
          subject_kinds: [subject_kind],
          default_filters: %{lifecycle_state: "awaiting_review"},
          sort: [{:inserted_at, :asc}],
          included_fields: [:subject_kind, :lifecycle_state]
        }
      ]
    }
  end

  def manifest(overrides), do: overrides |> Config.load() |> manifest()

  @spec pack_slug(Config.t() | keyword() | map()) :: String.t()
  def pack_slug(%Config{} = config), do: config.program_slug
  def pack_slug(overrides), do: overrides |> Config.load() |> pack_slug()

  @spec pack_version(Config.t() | keyword() | map()) :: String.t()
  def pack_version(%Config{} = config), do: config.pack_version
  def pack_version(overrides), do: overrides |> Config.load() |> pack_version()

  @spec execution_binding_key(Config.t() | keyword() | map()) :: String.t()
  def execution_binding_key(%Config{} = config),
    do: config |> execution_recipe_ref_atom() |> Atom.to_string()

  def execution_binding_key(overrides), do: overrides |> Config.load() |> execution_binding_key()

  @spec execution_recipe_ref(Config.t() | keyword() | map()) :: String.t()
  def execution_recipe_ref(%Config{} = config),
    do: config |> execution_recipe_ref_atom() |> Atom.to_string()

  def execution_recipe_ref(overrides), do: overrides |> Config.load() |> execution_recipe_ref()

  @spec placement_key(Config.t() | keyword() | map()) :: String.t()
  def placement_key(%Config{} = config), do: config |> placement_ref() |> Atom.to_string()
  def placement_key(overrides), do: overrides |> Config.load() |> placement_key()

  @spec source_binding_key(Config.t() | keyword() | map()) :: String.t()
  def source_binding_key(%Config{} = config),
    do: config |> source_binding_ref() |> Atom.to_string()

  def source_binding_key(overrides), do: overrides |> Config.load() |> source_binding_key()

  @spec profile_slots(Config.t() | keyword() | map()) :: map()
  def profile_slots(%Config{}) do
    %{
      source_profile_ref: :linear_coding_task,
      runtime_profile_ref: :codex_session,
      tool_scope_ref: :coding_ops_v1,
      evidence_profile_ref: :github_pr_plus_workpad,
      publication_profile_ref: :linear_workpad_review,
      review_profile_ref: :human_operator,
      memory_profile_ref: :none,
      projection_profile_ref: :coding_ops_projection_v1
    }
  end

  def profile_slots(overrides), do: overrides |> Config.load() |> profile_slots()

  @spec agent_loop_profile_slots(Config.t() | keyword() | map()) :: map()
  def agent_loop_profile_slots(%Config{} = config) do
    config
    |> profile_slots()
    |> Map.put(:memory_profile_ref, :private_facts_v1)
  end

  def agent_loop_profile_slots(overrides),
    do: overrides |> Config.load() |> agent_loop_profile_slots()

  defp subject_kind(%Config{} = config),
    do: fetch_ref!(@subject_kinds, config.work_class_kind, :work_class_kind)

  defp source_kind(%Config{} = config),
    do: fetch_ref!(@source_kinds, config.linear_source_kind, :linear_source_kind)

  defp source_binding_ref(%Config{} = config),
    do: fetch_ref!(@source_binding_refs, config.linear_source_kind, :source_binding_ref)

  defp execution_recipe_ref_atom(%Config{} = config),
    do: fetch_ref!(@recipe_refs, config.work_class_name, :work_class_name)

  defp placement_ref(%Config{} = config),
    do: fetch_ref!(@placement_refs, config.placement_profile_id, :placement_profile_id)

  defp fetch_ref!(refs, value, field) do
    case Map.fetch(refs, value) do
      {:ok, ref} ->
        ref

      :error ->
        raise ArgumentError, "unknown ProductPack #{field}: #{inspect(value)}"
    end
  end
end
