defmodule Extravaganza.ProductPack do
  @moduledoc """
  Product-owned pack definition for the default Extravaganza coding workflow.
  """

  @behaviour Mezzanine.Pack

  alias Extravaganza.Config

  alias Mezzanine.Pack.{
    ContextSourceSpec,
    DecisionSpec,
    EvidenceBinding,
    EvidenceSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    OperationDependency,
    OperationGraph,
    OperationRole,
    OperatorActionSpec,
    ProjectionSpec,
    ResourceEffectBinding,
    RuntimeBinding,
    SourceBinding,
    SourceBindingSpec,
    SourceKindSpec,
    SourcePublicationBinding,
    SourcePublishSpec,
    SubjectKindSpec,
    ToolBinding,
    WorkflowSpec
  }

  @subject_kinds %{"coding_task" => :coding_task}
  @source_kinds %{"linear" => :linear}
  @source_binding_refs %{"linear" => :linear_primary}
  @recipe_refs %{"coding_operations" => :coding_operations}
  @placement_refs %{"local_default" => :local_default}
  @binding_manifest_digest "sha256:extravaganza-coding-ops-generic-bindings-v1"
  @linear_connector_ref "jido/connectors/linear"
  @github_connector_ref "jido/connectors/github"
  @codex_connector_ref "jido/connectors/codex_cli"
  @linear_manifest_ref "manifest://jido/connectors/linear@local"
  @github_manifest_ref "manifest://jido/connectors/github@local"
  @codex_manifest_ref "manifest://jido/connectors/codex_cli@local"

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
      binding_specs: binding_specs(config),
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
      context_source_specs: [
        %ContextSourceSpec{
          source_ref: :workspace_memory,
          description: "Optional OuterBrain workspace memory context",
          binding_key: :shared_memory,
          usage_phase: :retrieval,
          required?: false,
          timeout_ms: 1_000,
          schema_ref: "context/workspace_memory",
          max_fragments: 3,
          merge_strategy: :ranked_append
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
          dynamic_tool_manifest: %{
            tools: [
              "linear.comments.update",
              "linear.graphql.execute",
              "github.pr.create",
              "github.pr.fetch",
              "github.pr.list",
              "github.pr.reviews.list",
              "github.pr.review_comments.list"
            ]
          },
          hook_stages: [:prepare_workspace, :after_turn],
          max_turns: 12,
          stall_timeout_ms: 300_000,
          execution_params: %{timeout_ms: config.execution_timeout_ms},
          applicable_to: [subject_kind]
        }
      ],
      operation_graph_specs: operation_graph_specs(recipe_ref),
      workflow_specs: workflow_specs(),
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
          action_kind: :pause,
          description: "Pause the active coding execution for operator review",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :pause_execution
        },
        %OperatorActionSpec{
          action_kind: :resume,
          description: "Resume a paused coding execution",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :resume_execution
        },
        %OperatorActionSpec{
          action_kind: :cancel,
          description: "Cancel the active coding execution",
          applicable_states: [:submitted, :awaiting_review, :retry_submission],
          authorized_roles: [:operator],
          effect: :cancel_active_execution
        },
        %OperatorActionSpec{
          action_kind: :rework,
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

  @spec source_binding_snapshot(Config.t() | keyword() | map(), map() | keyword()) :: map()
  def source_binding_snapshot(config_or_overrides, overrides \\ %{})

  def source_binding_snapshot(%Config{} = config, overrides) do
    source_binding_ref = source_binding_ref(config)
    source_binding_id = Atom.to_string(source_binding_ref)

    %{
      source_binding_id: source_binding_id,
      binding_ref: source_binding_id,
      compiled_binding_ref: "compiled-binding://#{pack_slug(config)}/#{source_binding_id}",
      adapter_ref: "linear",
      provider: "linear",
      connection_ref: source_binding_id,
      operation_refs: %{
        fetch_candidates: "linear.issues.list",
        current_states: "linear.issues.list",
        refresh_item: "linear.issues.retrieve",
        viewer: "linear.users.get_self"
      },
      state_mapping: %{
        "submitted" => ["Todo", "Backlog"],
        "retry_submission" => ["Todo"],
        "completed" => ["Done", "Completed"],
        "rejected" => ["Canceled", "Cancelled", "Duplicate"]
      }
    }
    |> Map.merge(Map.new(overrides))
  end

  def source_binding_snapshot(overrides, binding_overrides) do
    overrides
    |> Config.load()
    |> source_binding_snapshot(binding_overrides)
  end

  @spec workflow_role_refs(Config.t() | keyword() | map()) :: map()
  def workflow_role_refs(config_or_overrides \\ Config.load())

  def workflow_role_refs(%Config{} = config) do
    config
    |> manifest()
    |> Map.fetch!(:workflow_specs)
    |> List.first()
    |> case do
      %WorkflowSpec{} = workflow ->
        %{
          source_role_ref: workflow.source_role_ref,
          runtime_role_ref: workflow.runtime_role_ref,
          publication_role_ref: workflow.publication_role_ref,
          evidence_role_refs: workflow.evidence_role_refs,
          resource_effect_role_refs: workflow.resource_effect_role_refs,
          tool_role_refs: workflow.metadata[:tool_role_refs] || []
        }
    end
  end

  def workflow_role_refs(overrides), do: overrides |> Config.load() |> workflow_role_refs()

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

  defp binding_specs(%Config{} = config) do
    source_binding_ref = source_binding_ref(config)

    [
      %SourceBinding{
        binding_ref: source_binding_ref,
        source_kind: source_kind(config),
        subject_kind: subject_kind(config),
        connector_ref: @linear_connector_ref,
        manifest_ref: @linear_manifest_ref,
        operation_refs: %{
          fetch_candidates: "linear.issues.list",
          current_states: "linear.issues.list",
          refresh_item: "linear.issues.retrieve",
          viewer: "linear.users.get_self"
        },
        credential_binding_ref: :linear_primary,
        adapter_ref: :linear,
        connection_ref: :linear_primary,
        candidate_filter_ref: :linear_coding_task_filter,
        cursor_policy_ref: :linear_issue_polling,
        projection_profile_ref: :coding_ops_projection_v1,
        retry_policy_ref: :linear_read_retry,
        metadata:
          binding_metadata(
            %{
              fetch_candidates: :source_read,
              current_states: :source_read,
              refresh_item: :source_read,
              viewer: :source_read
            },
            %{fetch_candidates: :read, current_states: :read, refresh_item: :read, viewer: :read},
            %{
              fetch_candidates: ["read"],
              current_states: ["read"],
              refresh_item: ["read"],
              viewer: ["read"]
            }
          )
      },
      %SourcePublicationBinding{
        binding_ref: :linear_workpad_review,
        source_binding_ref: source_binding_ref,
        connector_ref: @linear_connector_ref,
        manifest_ref: @linear_manifest_ref,
        operation_refs: %{
          create_comment: "linear.comments.create",
          update_comment: "linear.comments.update",
          update_state: "linear.issues.update",
          list_states: "linear.workflow_states.list"
        },
        credential_binding_ref: :linear_primary,
        template_ref: :operator_review_workpad,
        publication_profile_ref: :linear_workpad_review,
        retry_policy_ref: :linear_write_retry,
        metadata:
          binding_metadata(
            %{
              create_comment: :source_write,
              update_comment: :source_write,
              update_state: :source_write,
              list_states: :source_read
            },
            %{
              create_comment: :write,
              update_comment: :write,
              update_state: :write,
              list_states: :read
            },
            %{
              create_comment: ["write"],
              update_comment: ["write"],
              update_state: ["write"],
              list_states: ["read"]
            }
          )
      },
      %RuntimeBinding{
        binding_ref: :codex_session,
        runtime_family: :session,
        connector_ref: @codex_connector_ref,
        manifest_ref: @codex_manifest_ref,
        operation_refs: %{
          session_turn: "codex.session.turn",
          session_start: "codex.session.start",
          session_stop: "codex.session.stop",
          session_status: "codex.session.status",
          session_stream: "codex.session.stream",
          session_cancel: "codex.session.cancel"
        },
        credential_binding_ref: :codex_session,
        session_policy_ref: :codex_app_server_session,
        tool_catalog_ref: :coding_ops_v1,
        retry_policy_ref: :codex_session_retry,
        metadata:
          binding_metadata(
            %{
              session_turn: :runtime_operation,
              session_start: :runtime_operation,
              session_stop: :runtime_operation,
              session_status: :runtime_operation,
              session_stream: :runtime_operation,
              session_cancel: :runtime_operation
            },
            %{
              session_turn: :write,
              session_start: :write,
              session_stop: :write,
              session_status: :read,
              session_stream: :write,
              session_cancel: :write
            },
            %{
              session_turn: ["session:execute"],
              session_start: ["session:execute"],
              session_stop: ["session:control"],
              session_status: ["session:control"],
              session_stream: ["session:execute"],
              session_cancel: ["session:control"]
            }
          )
      },
      %ToolBinding{
        binding_ref: :linear_graphql,
        runtime_binding_ref: :codex_session,
        connector_ref: @linear_connector_ref,
        manifest_ref: @linear_manifest_ref,
        operation_refs: %{execute_graphql: "linear.graphql.execute"},
        authorization_class: :runtime_tool_invocation,
        credential_binding_ref: :linear_primary,
        tool_schema_ref: :linear_graphql_tool,
        input_policy_ref: :linear_graphql_input_policy,
        retry_policy_ref: :linear_read_retry,
        metadata:
          binding_metadata(
            %{execute_graphql: :runtime_tool_invocation},
            %{execute_graphql: :read},
            %{execute_graphql: ["read"]}
          )
      },
      %EvidenceBinding{
        binding_ref: :github_pr,
        evidence_kind: :github_pr,
        connector_ref: @github_connector_ref,
        manifest_ref: @github_manifest_ref,
        operation_refs: %{
          fetch: "github.pr.fetch",
          reviews: "github.pr.reviews.list",
          review_comments: "github.pr.review_comments.list",
          combined_status: "github.commit.statuses.get_combined",
          check_runs: "github.check_runs.list_for_ref"
        },
        credential_binding_ref: :github_primary,
        collection_policy_ref: :github_pr_evidence_policy,
        retry_policy_ref: :github_read_retry,
        metadata:
          binding_metadata(
            %{
              fetch: :evidence_collection,
              reviews: :evidence_collection,
              review_comments: :evidence_collection,
              combined_status: :evidence_collection,
              check_runs: :evidence_collection
            },
            %{
              fetch: :read,
              reviews: :read,
              review_comments: :read,
              combined_status: :read,
              check_runs: :read
            },
            %{
              fetch: ["repo"],
              reviews: ["repo"],
              review_comments: ["repo"],
              combined_status: ["repo"],
              check_runs: ["repo"]
            }
          )
      },
      %ResourceEffectBinding{
        binding_ref: :github_pr_cleanup,
        effect_kind: :github_pr_branch_cleanup,
        connector_ref: @github_connector_ref,
        manifest_ref: @github_manifest_ref,
        operation_refs: %{
          list: "github.pr.list",
          comment: "github.comment.create",
          close: "github.pr.update"
        },
        operation_group_ref: :github_pr_branch_cleanup_group,
        credential_binding_ref: :github_primary,
        confirmation_policy_ref: :github_pr_cleanup_confirmation,
        retry_policy_ref: :github_write_retry,
        metadata:
          binding_metadata(
            %{list: :resource_effect, comment: :resource_effect, close: :resource_effect},
            %{list: :read, comment: :write, close: :write},
            %{list: ["repo"], comment: ["repo"], close: ["repo"]}
          )
      }
    ]
  end

  defp operation_graph_specs(recipe_ref) do
    [
      %OperationGraph{
        graph_ref: :coding_ops_operation_graph,
        workflow_ref: :coding_ops_workflow,
        roles: [
          %OperationRole{
            role_ref: :issue_tracker,
            binding_ref: :linear_primary,
            operation_role: :fetch_candidates,
            operation_class: :source_read,
            projection_order_key: 1
          },
          %OperationRole{
            role_ref: :coding_agent_runtime,
            binding_ref: :codex_session,
            operation_role: :session_turn,
            operation_class: :runtime_operation,
            projection_order_key: 2,
            metadata: %{recipe_ref: recipe_ref}
          },
          %OperationRole{
            role_ref: :issue_graphql_tool,
            binding_ref: :linear_graphql,
            operation_role: :execute_graphql,
            operation_class: :runtime_tool_invocation,
            projection_order_key: 3,
            completion_policy: :optional,
            failure_policy: :degrade
          },
          %OperationRole{
            role_ref: :proposed_change_evidence,
            binding_ref: :github_pr,
            operation_role: :fetch,
            operation_class: :evidence_collection,
            projection_order_key: 4,
            completion_policy: :optional,
            failure_policy: :degrade
          },
          %OperationRole{
            role_ref: :source_publication,
            binding_ref: :linear_workpad_review,
            operation_role: :update_comment,
            operation_class: :source_write,
            projection_order_key: 5
          },
          %OperationRole{
            role_ref: :proposed_change_cleanup,
            binding_ref: :github_pr_cleanup,
            operation_role: :list,
            operation_class: :resource_effect,
            projection_order_key: 6
          }
        ],
        dependencies: operation_dependencies()
      }
    ]
  end

  defp operation_dependencies do
    [
      %OperationDependency{
        from_role: :issue_tracker,
        to_role: :coding_agent_runtime,
        relation: :blocks_on_success
      },
      %OperationDependency{
        from_role: :coding_agent_runtime,
        to_role: :issue_graphql_tool,
        relation: :parallel_allowed,
        completion_policy: :optional,
        failure_policy: :degrade
      },
      %OperationDependency{
        from_role: :coding_agent_runtime,
        to_role: :proposed_change_evidence,
        relation: :parallel_allowed,
        completion_policy: :optional,
        failure_policy: :degrade
      },
      %OperationDependency{
        from_role: :coding_agent_runtime,
        to_role: :source_publication,
        relation: :blocks_on_success
      },
      %OperationDependency{
        from_role: :proposed_change_evidence,
        to_role: :source_publication,
        relation: :blocks_on_review,
        completion_policy: :optional,
        failure_policy: :degrade,
        review_policy_ref: :operator_review
      },
      %OperationDependency{
        from_role: :source_publication,
        to_role: :proposed_change_cleanup,
        relation: :blocks_on_confirmation,
        confirmation_policy_ref: :github_pr_cleanup_confirmation
      }
    ]
  end

  defp workflow_specs do
    [
      %WorkflowSpec{
        workflow_ref: :coding_ops_workflow,
        source_role_ref: :issue_tracker,
        runtime_role_ref: :coding_agent_runtime,
        publication_role_ref: :source_publication,
        evidence_role_refs: [:proposed_change_evidence],
        resource_effect_role_refs: [:proposed_change_cleanup],
        operation_graph_ref: :coding_ops_operation_graph,
        metadata: %{tool_role_refs: [:issue_graphql_tool]}
      }
    ]
  end

  defp binding_metadata(operation_classes, side_effect_classes, required_scopes) do
    %{
      manifest_digest: @binding_manifest_digest,
      operation_classes: operation_classes,
      side_effect_classes: side_effect_classes,
      required_scopes: required_scopes
    }
  end

  defp fetch_ref!(refs, value, field) do
    case Map.fetch(refs, value) do
      {:ok, ref} ->
        ref

      :error ->
        raise ArgumentError, "unknown ProductPack #{field}: #{inspect(value)}"
    end
  end
end
