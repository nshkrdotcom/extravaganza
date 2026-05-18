defmodule Extravaganza.ProviderImplApiStaticTest do
  use ExUnit.Case, async: true

  test "product implementation no longer exposes old provider-shaped API names" do
    offenders =
      "apps/extravaganza_core/lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.concat(Path.wildcard("apps/extravaganza_web/lib/**/*.ex"))
      |> Enum.flat_map(&provider_impl_token_hits/1)

    assert offenders == []
  end

  test "headless product intent API uses neutral names" do
    assert_public_function(Extravaganza.ProductHost, :sync_issue_tracker_source, 2)
    assert_public_function(Extravaganza.ProductHost, :sync_issue_tracker_item, 2)
    assert_public_function(Extravaganza.HeadlessSurface, :fetch_source_candidates, 2)
    assert_public_function(Extravaganza.HeadlessSurface, :current_source_states, 3)
    assert_public_function(Extravaganza.HeadlessSurface, :publish_source_update, 2)
    assert_public_function(Extravaganza.HeadlessSurface, :execute_issue_tracker_query_tool, 2)
    assert_public_function(Extravaganza.HeadlessSurface, :collect_proposed_change_evidence, 2)
    assert_public_function(Extravaganza.HeadlessSurface, :cleanup_proposed_change_branch, 2)
  end

  defp assert_public_function(module, function, arity) do
    assert Code.ensure_loaded?(module)
    assert function_exported?(module, function, arity)
  end

  defp old_provider_impl_tokens do
    linear = "linear"
    github = "github"

    [
      token(["sync", linear, "source"]),
      token(["sync", linear, "issue"]),
      token(["sync", linear, "issues"]),
      token(["fetch", linear, "candidates"]),
      token(["current", linear, "issue", "states"]),
      token(["publish", linear, "source"]),
      token(["execute", linear, "graphql", "tool"]),
      token(["fetch", github, "pr", "evidence"]),
      token(["cleanup", github, "pr", "branch"])
    ]
  end

  defp provider_impl_token_hits(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      old_provider_impl_tokens()
      |> Enum.filter(&String.contains?(line, &1))
      |> Enum.map(&{path, line_number, &1})
    end)
  end

  defp token(parts), do: Enum.join(parts, "_")
end
