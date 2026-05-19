defmodule Extravaganza.HeadlessLiveExamples.Registry do
  @moduledoc false

  @provider_examples %{
    linear_source: %{
      operation: "live.linear-source",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_source --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_source_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.users.get_self", "linear.issues.list", "linear.issues.retrieve"],
      provider_effect: "source_intake"
    },
    linear_current_states: %{
      operation: "live.linear-current-states",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_current_states --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_current_states_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.users.get_self", "linear.issues.list"],
      provider_effect: "source_current_state"
    },
    codex_turn: %{
      operation: "live.codex-turn",
      provider: "codex",
      command: "mix extravaganza.headless.live.codex_turn --json",
      product_entrypoint: "Extravaganza.ProductHost.live_codex_turn_example",
      credential_refs: ["OPENAI_API_KEY", "CODEX_API_KEY"],
      capability_ids: ["codex.session.turn"],
      provider_effect: "agent_turn"
    },
    linear_publication: %{
      operation: "live.linear-publication",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_publication --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_publication_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: [
        "linear.comments.update",
        "linear.comments.create",
        "linear.issues.update",
        "linear.workflow_states.list"
      ],
      provider_effect: "source_publication"
    },
    linear_graphql_tool: %{
      operation: "live.linear-graphql-tool",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_graphql_tool --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_graphql_tool_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.graphql.execute"],
      provider_effect: "dynamic_tool"
    },
    github_evidence: %{
      operation: "live.github-evidence",
      provider: "github",
      command: "mix extravaganza.headless.live.github_evidence --json",
      product_entrypoint: "Extravaganza.ProductHost.live_github_evidence_example",
      credential_refs: ["GH_TOKEN", "GITHUB_TOKEN"],
      capability_ids: [
        "github.pr.fetch",
        "github.pr.reviews.list",
        "github.pr.review_comments.list",
        "github.commit.statuses.get_combined",
        "github.check_runs.list_for_ref"
      ],
      provider_effect: "github_pr_evidence"
    },
    github_pr_cleanup: %{
      operation: "live.github-pr-cleanup",
      provider: "github",
      command: "mix extravaganza.headless.live.github_pr_cleanup --json",
      product_entrypoint: "Extravaganza.ProductHost.live_github_pr_cleanup_example",
      credential_refs: ["GH_TOKEN", "GITHUB_TOKEN"],
      capability_ids: ["github.pr.list", "github.comment.create", "github.pr.update"],
      provider_effect: "github_pr_branch_cleanup"
    }
  }

  @example_order [
    :linear_source,
    :linear_current_states,
    :codex_turn,
    :linear_publication,
    :linear_graphql_tool,
    :github_evidence
  ]

  @standalone_examples @example_order ++ [:github_pr_cleanup]

  @spec all() :: %{atom() => map()}
  def all, do: @provider_examples

  @spec example_order() :: [atom()]
  def example_order, do: @example_order

  @spec standalone_examples() :: [atom()]
  def standalone_examples, do: @standalone_examples

  @spec standalone_example?(atom()) :: boolean()
  def standalone_example?(kind), do: kind in @standalone_examples

  @spec fetch!(atom()) :: map()
  def fetch!(kind), do: Map.fetch!(@provider_examples, kind)
end
