defmodule Extravaganza.PolicyPresets do
  @moduledoc """
  Product-level policy preset accessors for the proving deployment.
  """

  alias Extravaganza.PolicyPresets.{DefaultCodingOps, DefaultReviewGates}

  @spec default_coding_ops() :: map()
  def default_coding_ops do
    %{
      name: "default_coding_ops",
      version: "1.0.0",
      policy_kind: :workflow_md,
      source_ref: "extravaganza/default_coding_ops",
      body: DefaultCodingOps.workflow_body(),
      metadata: %{"preset" => "default_coding_ops"}
    }
  end

  @spec default_review_gates() :: map()
  def default_review_gates do
    DefaultReviewGates.profile()
  end
end
