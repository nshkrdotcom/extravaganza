defmodule Extravaganza.Reviews do
  @moduledoc """
  Product-local review commands over AppKit.
  """

  alias AppKit.Core.DecisionRef
  alias AppKit.{OperatorSurface, ReviewSurface}
  alias Extravaganza.{Config, ProductSurface}

  @spec review_run(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_run(run_ref, evidence_attrs, opts \\ [])
      when is_map(evidence_attrs) and is_list(opts) do
    config = Config.load(opts)

    OperatorSurface.review_run(
      run_ref,
      evidence_attrs,
      ProductSurface.operator_opts(config, opts)
    )
  end

  @spec record_review_decision(DecisionRef.t() | map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def record_review_decision(review_identity, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)

    with {:ok, %{context: context}} <- ProductSurface.bootstrapped_context(opts) do
      review_attrs = Map.new(attrs)
      operator_opts = ProductSurface.operator_opts(config, opts)

      record_review_decision(context, review_identity, review_attrs, operator_opts)
    end
  end

  defp record_review_decision(context, review_identity, review_attrs, operator_opts) do
    case decision_ref(review_identity) do
      {:ok, decision_ref} ->
        ReviewSurface.record_decision(context, decision_ref, review_attrs, operator_opts)

      {:error, _reason} ->
        record_review_decision_by_id(context, review_identity, review_attrs, operator_opts)
    end
  end

  defp record_review_decision_by_id(context, review_identity, review_attrs, operator_opts) do
    with {:ok, decision_id} <- decision_id(review_identity) do
      ReviewSurface.record_decision_by_id(context, decision_id, review_attrs, operator_opts)
    end
  end

  defp decision_ref(%DecisionRef{} = decision_ref), do: {:ok, decision_ref}

  defp decision_ref(%{decision_ref: %DecisionRef{} = decision_ref}), do: {:ok, decision_ref}

  defp decision_ref(attrs) when is_map(attrs) do
    DecisionRef.new(%{
      id: map_value(attrs, :id) || get_in(attrs, [:decision_ref, :id]),
      decision_kind:
        map_value(attrs, :decision_kind) || get_in(attrs, [:decision_ref, :decision_kind]),
      subject_ref:
        map_value(attrs, :subject_ref) ||
          %{
            id: map_value(attrs, :subject_id) || get_in(attrs, [:subject_ref, :id]),
            subject_kind:
              map_value(attrs, :subject_kind) || get_in(attrs, [:subject_ref, :subject_kind])
          }
    })
  end

  defp decision_id(%DecisionRef{id: id}) when is_binary(id), do: {:ok, id}
  defp decision_id(%{decision_ref: %DecisionRef{id: id}}) when is_binary(id), do: {:ok, id}

  defp decision_id(attrs) when is_map(attrs) do
    case map_value(attrs, :id) || get_in(attrs, [:decision_ref, :id]) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _missing -> {:error, :missing_decision_id}
    end
  end

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
