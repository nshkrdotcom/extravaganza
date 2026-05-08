defmodule Extravaganza.PolicyPresets.DefaultCodingOps do
  @moduledoc """
  Default workflow-style policy bundle for Extravaganza coding operations.
  """

  alias Extravaganza.CodingOpsTemplates

  @prompt_artifact_ref %{
    prompt_id: "prompt://extravaganza/coding_agent_system",
    revision: 1,
    tenant_ref: "tenant://extravaganza/default",
    installation_ref: "installation://extravaganza/default",
    content_hash: "sha256:extravaganza-coding-agent-system-v1",
    redaction_policy_ref: "redaction://prompt/excerpt-only",
    lineage_ref: "prompt-lineage://extravaganza/coding_agent_system/1"
  }
  @guard_chain_ref %{
    guard_chain_ref: "guard-chain://extravaganza/coding_ops/default",
    detector_refs: [
      "detector://pii_reference",
      "detector://jailbreak_reference",
      "detector://schema_shape_reference",
      "detector://length_bounds"
    ],
    redaction_posture_floor: "partial",
    policy_revision_ref: "policy-revision://extravaganza/coding_ops/guard/v1"
  }
  @budget_policy_ref "budget-policy://extravaganza/coding_ops/default"

  @spec workflow_body() :: String.t()
  def workflow_body do
    """
    # Extravaganza Coding Agent

    Prompt artifact ref: #{@prompt_artifact_ref.prompt_id}
    Prompt artifact revision: #{@prompt_artifact_ref.revision}
    Prompt catalog key: #{CodingOpsTemplates.prompt_ref()}
    Guard chain ref: #{@guard_chain_ref.guard_chain_ref}
    Budget policy ref: #{@budget_policy_ref}
    """
  end

  @spec prompt_artifact_ref() :: map()
  def prompt_artifact_ref, do: @prompt_artifact_ref

  @spec guard_chain_ref() :: map()
  def guard_chain_ref, do: @guard_chain_ref

  @spec budget_policy_ref() :: String.t()
  def budget_policy_ref, do: @budget_policy_ref

  @spec budget_policy() :: map()
  def budget_policy do
    %{
      budget_policy_ref: @budget_policy_ref,
      citadel_policy_ref: "policy://citadel/coding_ops/budget/default",
      scope_key_ref: "budget-scope://coding-ops/default",
      period_class: "per_run",
      hard_cap_class: "redacted_above_ceiling",
      soft_cap_class: "redacted_below_floor",
      default_exhaustion_behavior: "fail_closed",
      override_permissions: [
        %{
          permission_ref: "permission://budget/override",
          operator_role_refs: ["role://operator/coding-ops-budget-override"],
          budget_classes: ["production", "replay", "eval", "infrastructure"],
          max_duration_seconds: 3_600,
          extensions: %{"policy_family" => "coding_ops_budget_override"}
        }
      ],
      extensions: %{"policy_family" => "coding_ops_budget"}
    }
  end

  @spec prompt_author_request() :: map()
  def prompt_author_request do
    {:ok, request} =
      AppKit.PromptSurface.author_request(%{
        request_ref: "prompt-author-request://extravaganza/coding_agent_system/v1",
        tenant_ref: @prompt_artifact_ref.tenant_ref,
        authority_ref: "authority://extravaganza/default-authoring",
        installation_ref: @prompt_artifact_ref.installation_ref,
        prompt_id: @prompt_artifact_ref.prompt_id,
        content_hash: @prompt_artifact_ref.content_hash
      })

    Map.from_struct(request)
  end

  @spec runtime_config() :: map()
  def runtime_config do
    %{
      "tracker" => %{
        "kind" => "linear",
        "endpoint" => "https://api.linear.app/graphql"
      },
      "run" => %{
        "profile" => "default_codex",
        "runtime_class" => "session",
        "lower_runtime_kind" => "codex_session",
        "capability" => "codex.session.turn",
        "target" => "codex-default"
      },
      "approval" => %{
        "mode" => "manual",
        "reviewers" => ["ops_lead"],
        "escalation_required" => true
      },
      "retry" => %{
        "strategy" => "linear",
        "max_attempts" => 2,
        "initial_backoff_ms" => 5_000,
        "max_backoff_ms" => 300_000
      },
      "placement" => %{
        "profile_id" => "local_default",
        "strategy" => "affinity",
        "target_selector" => %{
          "runtime_driver" => "jido_session"
        },
        "runtime_preferences" => %{
          "locality" => "same_region"
        }
      },
      "workspace" => %{
        "root_mode" => "per_work",
        "sandbox_profile" => "strict"
      },
      "review" => %{
        "required" => true,
        "required_decisions" => 1,
        "gates" => ["operator"]
      },
      "budget" => %{
        "budget_policy_ref" => @budget_policy_ref,
        "default_budget_ref" => "budget://extravaganza/coding_ops/default",
        "cost_class" => "production",
        "fail_closed" => true
      },
      "capability_grants" => [
        %{"capability_id" => "codex.session.turn", "mode" => "allow"},
        %{"capability_id" => "linear.issues.list", "mode" => "allow"},
        %{"capability_id" => "linear.issues.retrieve", "mode" => "allow"},
        %{"capability_id" => "linear.issues.update", "mode" => "allow"},
        %{"capability_id" => "linear.comments.create", "mode" => "allow"},
        %{"capability_id" => "linear.comments.update", "mode" => "allow"},
        %{"capability_id" => "linear.graphql.execute", "mode" => "allow"},
        %{"capability_id" => "github.pr.create", "mode" => "allow"},
        %{"capability_id" => "github.pr.fetch", "mode" => "allow"},
        %{"capability_id" => "github.pr.update", "mode" => "allow"},
        %{"capability_id" => "github.pr.reviews.list", "mode" => "allow"},
        %{"capability_id" => "github.pr.review_comments.list", "mode" => "allow"},
        %{"capability_id" => "github.pr.review.create", "mode" => "allow"},
        %{"capability_id" => "github.pr.review_comment.create", "mode" => "allow"},
        %{"capability_id" => "github.commit.statuses.get_combined", "mode" => "allow"},
        %{"capability_id" => "github.check_runs.list_for_ref", "mode" => "allow"}
      ]
    }
  end
end
