defmodule Extravaganza.HeadlessLiveExamples.Lanes.LinearPublication do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.linear_publication_effect(example, proof, opts)
end
