defmodule Extravaganza.HeadlessLiveExamples.Lanes.LinearGraphQLTool do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Lanes

  @spec effect(map(), map(), map()) :: map()
  def effect(example, proof, opts), do: Lanes.linear_graphql_tool_effect(example, proof, opts)
end
