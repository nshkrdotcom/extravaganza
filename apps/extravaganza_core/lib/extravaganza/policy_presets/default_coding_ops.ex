defmodule Extravaganza.PolicyPresets.DefaultCodingOps do
  @moduledoc """
  Default workflow-style policy bundle for Extravaganza coding operations.
  """

  alias Extravaganza.CodingOpsTemplates

  @spec workflow_body() :: String.t()
  def workflow_body do
    """
    ---
    tracker:
      kind: linear
      endpoint: https://api.linear.app/graphql
    run:
      profile: default_codex
      runtime_class: session
      capability: codex.task.execute
      target: codex-default
    approval:
      mode: manual
      reviewers:
        - ops_lead
      escalation_required: true
    retry:
      strategy: exponential
      max_attempts: 4
      initial_backoff_ms: 5000
      max_backoff_ms: 300000
    placement:
      profile_id: local_default
      strategy: affinity
      target_selector:
        runtime_driver: jido_session
      runtime_preferences:
        locality: same_region
    workspace:
      root_mode: per_work
      sandbox_profile: strict
    review:
      required: true
      required_decisions: 1
      gates:
        - operator
    capability_grants:
      - capability_id: linear.issue.read
        mode: allow
      - capability_id: linear.issue.update
        mode: allow
      - capability_id: github.issue.read
        mode: allow
      - capability_id: github.pull_request.write
        mode: allow
    ---
    #{CodingOpsTemplates.system_prompt()}
    """
  end
end
