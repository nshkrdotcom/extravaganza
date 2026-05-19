defmodule Extravaganza.HeadlessCLI.OperationRegistry do
  @moduledoc false

  @guardrails_ack_flag "--ack-headless-guardrails"
  @legacy_guardrails_ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"
  @guardrails_ack_flags [@guardrails_ack_flag, @legacy_guardrails_ack_flag]

  @operation_specs [
    %{
      operation: :state,
      envelope_name: "state",
      mix_tasks: ["extravaganza.headless.state"]
    },
    %{
      operation: :queue,
      envelope_name: "queue",
      mix_tasks: ["extravaganza.headless.queue"]
    },
    %{
      operation: :subject,
      envelope_name: "subject",
      mix_tasks: ["extravaganza.headless.subject"]
    },
    %{operation: :run, envelope_name: "run", mix_tasks: ["extravaganza.headless.run"]},
    %{
      operation: :start,
      envelope_name: "start",
      mix_tasks: ["extravaganza.headless.start"],
      mutating?: true
    },
    %{
      operation: :refresh,
      envelope_name: "refresh",
      mix_tasks: ["extravaganza.headless.refresh"],
      mutating?: true
    },
    %{
      operation: :control,
      envelope_name: "control",
      mix_tasks: ["extravaganza.headless.control"],
      mutating?: true
    },
    %{
      operation: :reviews,
      envelope_name: "reviews",
      mix_tasks: ["extravaganza.headless.reviews"]
    },
    %{
      operation: :review,
      envelope_name: "review",
      mix_tasks: ["extravaganza.headless.review"],
      mutating?: true
    },
    %{
      operation: :source_preview,
      envelope_name: "source_preview",
      mix_tasks: ["extravaganza.headless.source_preview"]
    },
    %{
      operation: :source_sync,
      envelope_name: "source_sync",
      mix_tasks: ["extravaganza.headless.source.sync", "extravaganza.headless.source_sync"],
      mutating?: true
    },
    %{
      operation: :source_publish,
      envelope_name: "source_publish",
      mix_tasks: ["extravaganza.headless.source_publish"],
      mutating?: true
    },
    %{
      operation: :profile,
      envelope_name: "profile",
      mix_tasks: ["extravaganza.headless.profile"]
    },
    %{
      operation: :profile_reload,
      envelope_name: "profile_reload",
      mix_tasks: ["extravaganza.headless.profile_reload"],
      mutating?: true
    },
    %{
      operation: :profile_validate,
      envelope_name: "profile_validate",
      mix_tasks: ["extravaganza.headless.profile_validate"]
    },
    %{
      operation: :status,
      envelope_name: "status",
      mix_tasks: ["extravaganza.headless.status"]
    },
    %{operation: :logs, envelope_name: "logs", mix_tasks: ["extravaganza.headless.logs"]},
    %{
      operation: :preflight,
      envelope_name: "preflight",
      mix_tasks: ["extravaganza.headless.preflight"]
    },
    %{
      operation: :stop,
      envelope_name: "stop",
      mix_tasks: ["extravaganza.headless.stop"],
      mutating?: true
    },
    %{
      operation: :live_linear_source,
      envelope_name: "live.linear-source",
      mix_tasks: [
        "extravaganza.headless.live.linear_source",
        "extravaganza.headless.live_linear_source"
      ],
      live?: true
    },
    %{
      operation: :live_linear_current_states,
      envelope_name: "live.linear-current-states",
      mix_tasks: [
        "extravaganza.headless.live.linear_current_states",
        "extravaganza.headless.live_linear_current_states"
      ],
      live?: true
    },
    %{
      operation: :live_codex_turn,
      envelope_name: "live.codex-turn",
      mix_tasks: [
        "extravaganza.headless.live.codex_turn",
        "extravaganza.headless.live_codex_turn"
      ],
      live?: true
    },
    %{
      operation: :live_linear_publication,
      envelope_name: "live.linear-publication",
      mix_tasks: [
        "extravaganza.headless.live.linear_publication",
        "extravaganza.headless.live_linear_publication"
      ],
      live?: true
    },
    %{
      operation: :live_linear_graphql_tool,
      envelope_name: "live.linear-graphql-tool",
      mix_tasks: [
        "extravaganza.headless.live.linear_graphql_tool",
        "extravaganza.headless.live_linear_graphql_tool"
      ],
      live?: true
    },
    %{
      operation: :live_github_evidence,
      envelope_name: "live.github-evidence",
      mix_tasks: [
        "extravaganza.headless.live.github_evidence",
        "extravaganza.headless.live_github_evidence"
      ],
      live?: true
    },
    %{
      operation: :live_github_pr_cleanup,
      envelope_name: "live.github-pr-cleanup",
      mix_tasks: [
        "extravaganza.headless.live.github_pr_cleanup",
        "extravaganza.headless.live_github_pr_cleanup"
      ],
      live?: true
    },
    %{
      operation: :live_smoke,
      envelope_name: "live.smoke",
      mix_tasks: ["extravaganza.headless.live.smoke", "extravaganza.headless.live_smoke"],
      live?: true
    },
    %{
      operation: :evidence,
      envelope_name: "evidence",
      mix_tasks: ["extravaganza.headless.evidence"]
    },
    %{
      operation: :events,
      envelope_name: "events",
      mix_tasks: ["extravaganza.headless.events"]
    },
    %{operation: :smoke, envelope_name: "smoke", mix_tasks: ["extravaganza.headless.smoke"]}
  ]

  @operations for %{operation: operation} <- @operation_specs, do: operation
  @live_operations for %{operation: operation, live?: true} <- @operation_specs, do: operation
  @mutating_operations for %{operation: operation, mutating?: true} <- @operation_specs,
                           do: operation

  @operation_envelope_names Map.new(@operation_specs, fn spec ->
                              {spec.operation, spec.envelope_name}
                            end)

  @spec operation_specs() :: [map()]
  def operation_specs, do: @operation_specs

  @spec operations() :: [atom()]
  def operations, do: @operations

  @spec operation?(atom()) :: boolean()
  def operation?(operation), do: operation in @operations

  @spec live_operation?(atom()) :: boolean()
  def live_operation?(operation), do: operation in @live_operations

  @spec mutating_operation?(atom()) :: boolean()
  def mutating_operation?(operation), do: operation in @mutating_operations

  @spec envelope_name(atom()) :: atom() | String.t()
  def envelope_name(operation), do: Map.get(@operation_envelope_names, operation, operation)

  @spec guardrails_ack_flags() :: [String.t()]
  def guardrails_ack_flags, do: @guardrails_ack_flags

  @spec maybe_default_live_fixture(map(), atom()) :: map()
  def maybe_default_live_fixture(%{live_product_path?: true} = opts, _operation), do: opts
  def maybe_default_live_fixture(%{fixture: _fixture} = opts, _operation), do: opts

  def maybe_default_live_fixture(opts, operation) do
    if live_operation?(operation), do: Map.put(opts, :fixture, "headless_live"), else: opts
  end
end
