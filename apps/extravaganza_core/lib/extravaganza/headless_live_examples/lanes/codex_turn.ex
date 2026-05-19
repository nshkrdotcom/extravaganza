defmodule Extravaganza.HeadlessLiveExamples.Lanes.CodexTurn do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.codex_turn_effect(example, proof, opts)
end
