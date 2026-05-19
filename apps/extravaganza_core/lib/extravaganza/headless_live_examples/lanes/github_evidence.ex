defmodule Extravaganza.HeadlessLiveExamples.Lanes.GitHubEvidence do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.github_evidence_effect(example, proof, opts)
end
