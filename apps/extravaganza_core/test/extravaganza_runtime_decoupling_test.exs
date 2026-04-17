defmodule Extravaganza.RuntimeDecouplingTest do
  use ExUnit.Case, async: true

  @forbidden_legacy_refs [
    ~r/Mezzanine\.OpsDomain\.Repo\b/,
    ~r/Mezzanine\.Programs\b/,
    ~r/Mezzanine\.Work\b/,
    ~r/Mezzanine\.Runs\b/,
    ~r/Mezzanine\.Review\b/,
    ~r/Mezzanine\.Evidence\b/,
    ~r/Mezzanine\.Control\b/
  ]
  @scan_patterns [
    "config/*.exs",
    "apps/extravaganza_core/lib/**/*.ex",
    "apps/extravaganza_core/test/extravaganza_product_core_test.exs",
    "apps/extravaganza_web/lib/**/*.ex",
    "apps/extravaganza_web/test/support/**/*.ex"
  ]

  test "product config and test support do not directly reference legacy mezzanine runtime modules" do
    root = Path.expand("../../..", __DIR__)

    Enum.each(@forbidden_legacy_refs, fn pattern ->
      assert_refutes_file_patterns(root, @scan_patterns, pattern)
    end)
  end

  defp assert_refutes_file_patterns(root, patterns, pattern) do
    patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(root, pattern), match_dot: true)
    end)
    |> Enum.uniq()
    |> Enum.each(fn path ->
      refute Regex.match?(pattern, File.read!(path)),
             "#{path} still references #{inspect(pattern)}"
    end)
  end
end
