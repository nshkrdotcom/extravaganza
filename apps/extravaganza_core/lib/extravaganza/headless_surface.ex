defmodule Extravaganza.HeadlessSurface do
  @moduledoc """
  Product-local M1 facade over AppKit readback and control surfaces.

  Extravaganza owns profile defaults and presentation. AppKit owns the product
  boundary, so this module builds product context and delegates to AppKit
  surfaces only.
  """

  alias AppKit.Core.RuntimeReadback.ControlRequest
  alias AppKit.HeadlessSurface, as: AppKitHeadlessSurface
  alias Extravaganza.{AppKitContext, Config, Operators, ProductSurface, Queries, Reviews}

  @actor_ref "actor:extravaganza:operator"

  @spec state_snapshot(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def state_snapshot(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{context: context}} <- context_bundle(opts) do
      AppKitHeadlessSurface.state_snapshot(context, Map.new(params), opts)
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
    Queries.pending_reviews(params, opts)
  end

  @spec record_review_decision(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def record_review_decision(review_identity, attrs \\ %{}, opts \\ [])
      when is_map(review_identity) and is_map(attrs) and is_list(opts) do
    Reviews.record_review_decision(review_identity, attrs, opts)
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
