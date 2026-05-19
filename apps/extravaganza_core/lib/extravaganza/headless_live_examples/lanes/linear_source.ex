defmodule Extravaganza.HeadlessLiveExamples.Lanes.LinearSource do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.linear_source_effect(example, proof, opts)
end
