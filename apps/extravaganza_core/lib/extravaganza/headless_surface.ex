defmodule Extravaganza.HeadlessSurface do
  @moduledoc """
  Product-local M1 facade over AppKit readback and control surfaces.

  Extravaganza owns profile defaults and presentation. AppKit owns the product
  boundary, so this module builds product context and delegates to AppKit
  surfaces only.
  """

  alias AppKit.Core.RuntimeReadback.{CommandResult, ControlRequest, RuntimeStateSnapshot}
  alias AppKit.HeadlessSurface, as: AppKitHeadlessSurface
  alias AppKit.RuntimeSurface, as: AppKitRuntimeSurface
  alias AppKit.SourceSurface, as: AppKitSourceSurface

  alias Extravaganza.{
    AppKitContext,
    Config,
    HeadlessReadback,
    Operators,
    ProductSurface,
    Queries,
    Reviews,
    Sources
  }

  @actor_ref "actor:extravaganza:operator"

  @spec state_snapshot(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def state_snapshot(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitHeadlessSurface.state_snapshot(context, Map.new(params), opts)
    end
  end

  @spec operator_queue(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def operator_queue(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    if fixture_context?() do
      with {:ok, %RuntimeStateSnapshot{} = snapshot} <- state_snapshot(params, opts) do
        {:ok,
         %{
           page: %{
             entries: snapshot.rows,
             total_count: length(snapshot.rows),
             has_more: false,
             next_cursor: nil
           },
           stats: %{"source" => "headless_fixture"}
         }}
      end
    else
      Queries.operator_queue(params, opts)
    end
  end

  @spec subject_detail(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def subject_detail(subject_id, params \\ %{}, opts \\ [])
      when is_binary(subject_id) and is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitHeadlessSurface.subject_detail(context, subject_id, Map.new(params), opts)
    end
  end

  @spec subject_by_issue_identifier(String.t(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def subject_by_issue_identifier(issue_identifier, params \\ %{}, opts \\ [])
      when is_binary(issue_identifier) and is_map(params) and is_list(opts) do
    subject_detail(issue_identifier, Map.put(params, "source_object_ref", issue_identifier), opts)
  end

  @spec run_detail(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def run_detail(run_id, params \\ %{}, opts \\ [])
      when is_binary(run_id) and is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitHeadlessSurface.run_detail(context, run_id, Map.new(params), opts)
    end
  end

  @spec evidence_chain(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def evidence_chain(run_id, params \\ %{}, opts \\ [])
      when is_binary(run_id) and is_map(params) and is_list(opts) do
    with {:ok, run} <- run_detail(run_id, params, opts) do
      {:ok, HeadlessReadback.evidence_chain(run)}
    end
  end

  @spec events(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def events(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with run_id when is_binary(run_id) <- map_value(params, :run_id) || map_value(params, :run),
         {:ok, run} <- run_detail(run_id, params, opts) do
      {:ok, HeadlessReadback.event_page(run, params)}
    else
      nil -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec request_refresh(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def request_refresh(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- context_bundle(opts) do
      request = %{
        idempotency_key: idempotency_key(attrs, "refresh"),
        actor_ref: actor_ref(attrs),
        scope_ref: scope_ref(config, attrs),
        operations: operations(attrs),
        reason: map_value(attrs, :reason)
      }

      AppKitHeadlessSurface.request_refresh(context, request, opts)
    end
  end

  @spec request_control(String.t(), atom() | String.t(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def request_control(subject_id, action, attrs \\ %{}, opts \\ [])
      when is_binary(subject_id) and is_map(attrs) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts),
         {:ok, action} <- normalize_control_action(action) do
      request = %{
        idempotency_key: idempotency_key(attrs, action),
        actor_ref: actor_ref(attrs),
        subject_ref: subject_id,
        action: action,
        params:
          Map.drop(Map.new(attrs), [:idempotency_key, "idempotency_key", :actor_ref, "actor_ref"])
      }

      AppKitHeadlessSurface.request_control(context, request, opts)
    end
  end

  @spec issue_read_lease(String.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def issue_read_lease(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    Operators.issue_read_lease(subject_id, opts)
  end

  @spec issue_stream_attach_lease(String.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def issue_stream_attach_lease(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    Operators.issue_stream_attach_lease(subject_id, opts)
  end

  @spec list_reviews(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_reviews(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    if fixture_context?(),
      do: {:ok, fixture_reviews()},
      else: Queries.pending_reviews(params, opts)
  end

  @spec record_review_decision(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def record_review_decision(review_identity, attrs \\ %{}, opts \\ [])
      when is_map(review_identity) and is_map(attrs) and is_list(opts) do
    if fixture_context?() do
      fixture_review_decision(review_identity, attrs)
    else
      Reviews.record_review_decision(review_identity, attrs, opts)
    end
  end

  @spec source_publication_preview(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def source_publication_preview(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    if fixture_context?() do
      with {:ok, evidence} <- evidence_chain("run:fixture", %{"subject_id" => subject_id}, opts) do
        {:ok, Map.fetch!(evidence, "source_publication")}
      end
    else
      Operators.source_publication_preview(subject_id, opts)
    end
  end

  @spec sync_linear_source(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_linear_source(source_page, opts \\ [])
      when is_map(source_page) and is_list(opts) do
    Sources.sync_linear_issues(source_page, opts)
  end

  @spec fetch_linear_candidates(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_linear_candidates(source_binding, opts \\ [])
      when is_map(source_binding) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitSourceSurface.fetch_linear_candidates(context, source_binding, opts)
    end
  end

  @spec publish_linear_source(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish_linear_source(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitSourceSurface.publish_linear_source(context, attrs, opts)
    end
  end

  @spec apply_runtime_profile(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def apply_runtime_profile(runtime_profile, opts \\ [])
      when is_map(runtime_profile) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitRuntimeSurface.apply_runtime_profile(context, runtime_profile, opts)
    end
  end

  @spec runtime_status(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def runtime_status(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitRuntimeSurface.runtime_status(context, Map.new(params), opts)
    end
  end

  @spec runtime_logs(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def runtime_logs(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitRuntimeSurface.runtime_logs(context, Map.new(params), opts)
    end
  end

  @spec record_live_effect(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def record_live_effect(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitRuntimeSurface.record_live_effect(context, attrs, opts)
    end
  end

  defp normalize_control_action(action)
       when action in [:pause, :resume, :cancel, :retry, :rework],
       do: {:ok, action}

  defp normalize_control_action(action) when action in ~w[pause resume cancel retry rework],
    do: {:ok, action}

  defp normalize_control_action("request_rework"), do: {:ok, "rework"}
  defp normalize_control_action(:request_rework), do: {:ok, :rework}
  defp normalize_control_action("pause_execution"), do: {:ok, "pause"}
  defp normalize_control_action(:pause_execution), do: {:ok, :pause}
  defp normalize_control_action("resume_execution"), do: {:ok, "resume"}
  defp normalize_control_action(:resume_execution), do: {:ok, :resume}
  defp normalize_control_action("cancel_execution"), do: {:ok, "cancel"}
  defp normalize_control_action(:cancel_execution), do: {:ok, :cancel}
  defp normalize_control_action(_action), do: {:error, :invalid_action}

  defp context_bundle(opts) do
    if Keyword.get(opts, :skip_bootstrap?) ||
         Application.get_env(:extravaganza_core, :headless_fixture_context?, false) do
      config = Config.load(opts)
      {:ok, %{config: config, context: AppKitContext.bootstrap_context(config), profile: %{}}}
    else
      ProductSurface.bootstrapped_context(opts)
    end
  end

  defp fixture_context?,
    do: Application.get_env(:extravaganza_core, :headless_fixture_context?, false)

  defp fixture_reviews do
    %{
      page: %{
        entries: [
          %{
            decision_ref: %{
              id: "decision:fixture",
              decision_kind: "operator_review",
              subject_id: "subject:fixture",
              subject_kind: "linear_issue"
            },
            subject_ref: %{id: "subject:fixture", subject_kind: "linear_issue"},
            status: "pending",
            summary: "Fixture review pending",
            required_by: "2026-05-08T00:00:00Z"
          }
        ],
        total_count: 1,
        has_more: false,
        next_cursor: nil
      }
    }
  end

  defp fixture_review_decision(review_identity, attrs) do
    decision_id = map_value(review_identity, :id) || "decision:fixture"
    decision = map_value(attrs, :decision) || "accept"

    CommandResult.new(%{
      command_ref: "command://review/#{decision_id}",
      command_kind: :review_decision,
      accepted?: true,
      coalesced?: false,
      status: :accepted,
      authority_state: :allowed,
      authority_refs: ["authority:fixture"],
      workflow_effect_state: "pending_signal",
      projection_state: :pending,
      trace_id: "trace:fixture:review",
      correlation_id: "corr:fixture-review",
      receipt_ref: "review-decision:fixture:#{decision}",
      idempotency_key: map_value(attrs, :idempotency_key) || "idem:fixture-review",
      message: "Fixture review decision accepted"
    })
  end

  defp idempotency_key(attrs, fallback) do
    map_value(attrs, :idempotency_key) ||
      "extravaganza:#{fallback}:#{System.unique_integer([:positive])}"
  end

  defp actor_ref(attrs), do: map_value(attrs, :actor_ref) || @actor_ref

  defp scope_ref(%Config{} = config, attrs),
    do: map_value(attrs, :scope_ref) || "scope:#{config.program_slug}"

  defp operations(attrs) do
    case map_value(attrs, :operations) do
      value when is_list(value) -> value
      nil -> ["state_snapshot"]
      value -> [value]
    end
  end

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  @doc false
  @spec control_request_schema() :: module()
  def control_request_schema, do: ControlRequest
end
