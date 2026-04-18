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

    with {:ok, %{context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, decision_ref} <- decision_ref(review_identity) do
      ReviewSurface.record_decision(
        context,
        decision_ref,
        Map.new(attrs),
        ProductSurface.operator_opts(config, opts)
      )
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

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
