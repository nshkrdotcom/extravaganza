defmodule Extravaganza.HeadlessLiveExamples.Lanes.GitHubCleanup do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.github_pr_cleanup_effect(example, proof, opts)
end
