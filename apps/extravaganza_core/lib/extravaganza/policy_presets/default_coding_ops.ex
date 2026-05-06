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

  @spec workflow_body() :: String.t()
  def workflow_body do
    """
    # Extravaganza Coding Agent

    Prompt artifact ref: #{@prompt_artifact_ref.prompt_id}
    Prompt artifact revision: #{@prompt_artifact_ref.revision}
    Prompt catalog key: #{CodingOpsTemplates.prompt_ref()}
    Guard chain ref: #{@guard_chain_ref.guard_chain_ref}
    """
  end

  @spec prompt_artifact_ref() :: map()
  def prompt_artifact_ref, do: @prompt_artifact_ref

  @spec guard_chain_ref() :: map()
  def guard_chain_ref, do: @guard_chain_ref

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
        "capability" => "codex.task.execute",
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
      "capability_grants" => [
        %{"capability_id" => "linear.issue.read", "mode" => "allow"},
        %{"capability_id" => "linear.issue.update", "mode" => "allow"},
        %{"capability_id" => "github.issue.read", "mode" => "allow"},
        %{"capability_id" => "github.pull_request.write", "mode" => "allow"}
      ]
    }
  end
end
