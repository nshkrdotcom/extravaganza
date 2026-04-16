defmodule Extravaganza.PolicyPresets.DefaultReviewGates do
  @moduledoc """
  Default review posture for Extravaganza coding operations.
  """

  @spec profile() :: map()
  def profile do
    %{
      "required" => true,
      "required_decisions" => 1,
      "mode" => "human_operator",
      "escalation_required" => true
    }
  end
end
