defmodule Extravaganza.RuntimeEnvApiStaticTest do
  use ExUnit.Case, async: true

  @forbidden_system_env_calls [:get_env, :fetch_env, :fetch_env!, :put_env, :delete_env]
  @runtime_source_patterns [
    "apps/extravaganza_core/lib/**/*.ex",
    "apps/extravaganza_web/lib/**/*.ex",
    "scripts/headless/*.exs",
    "scripts/headless/**/*.exs"
  ]

  test "runtime paths do not call direct OS env APIs" do
    root = Path.expand("../../..", __DIR__)

    violations =
      root
      |> runtime_source_paths()
      |> Enum.flat_map(&forbidden_system_env_calls(&1, root))
      |> Enum.sort()

    assert violations == [],
           "Forbidden direct OS env API calls in runtime/product paths:\n" <>
             Enum.join(violations, "\n")
  end

  defp runtime_source_paths(root) do
    @runtime_source_patterns
    |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(root, pattern)) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp forbidden_system_env_calls(path, root) do
    source = File.read!(path)

    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        collect_forbidden_system_env_calls(ast, path, root)

      {:error, {line, error, token}} ->
        relative_path = Path.relative_to(path, root)
        ["#{relative_path}:#{line} parse_error #{inspect(error)} #{inspect(token)}"]
    end
  end

  defp collect_forbidden_system_env_calls(ast, path, root) do
    {_ast, violations} =
      Macro.prewalk(ast, [], fn
        {{:., dot_meta, [{:__aliases__, _alias_meta, [:System]}, function]}, call_meta, args} =
            node,
        violations ->
          if function in @forbidden_system_env_calls do
            line = Keyword.get(call_meta, :line) || Keyword.get(dot_meta, :line) || 1
            arity = length(args || [])
            relative_path = Path.relative_to(path, root)

            {node, ["#{relative_path}:#{line} System.#{function}/#{arity}" | violations]}
          else
            {node, violations}
          end

        node, violations ->
          {node, violations}
      end)

    violations
  end
end
