defmodule Extravaganza.HeadlessLiveExamples.Lanes.LinearCurrentStates do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.linear_current_states_effect(example, proof, opts)
end
