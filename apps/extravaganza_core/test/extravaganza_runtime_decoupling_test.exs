defmodule Extravaganza.RuntimeDecouplingTest do
  use ExUnit.Case, async: true

  @forbidden_legacy_refs [
    "Mezzanine.OpsDomain.Repo",
    "Mezzanine.Programs",
    "Mezzanine.Work",
    "Mezzanine.Runs",
    "Mezzanine.Review",
    "Mezzanine.Evidence",
    "Mezzanine.Control"
  ]
  @scan_patterns [
    "config/*.exs",
    "apps/extravaganza_core/lib/**/*.ex",
    "apps/extravaganza_core/test/extravaganza_product_core_test.exs",
    "apps/extravaganza_web/lib/**/*.ex",
    "apps/extravaganza_web/test/support/**/*.ex"
  ]
  @active_product_patterns [
    "config/*.exs",
    "apps/extravaganza_core/lib/**/*.ex",
    "apps/extravaganza_web/lib/**/*.ex"
  ]

  test "product config and test support do not directly reference legacy mezzanine runtime modules" do
    root = Path.expand("../../..", __DIR__)

    Enum.each(@forbidden_legacy_refs, fn pattern ->
      assert_refutes_file_patterns(root, @scan_patterns, pattern)
    end)
  end

  test "active product code does not expose fake source adapters or old subject aliases" do
    root = Path.expand("../../..", __DIR__)

    assert_refutes_file_patterns(root, @active_product_patterns, "LinearIntakeAdapter")

    assert_refutes_normalized_file_patterns(
      root,
      @active_product_patterns,
      "subject_kind: \"work_object\""
    )
  end

  defp assert_refutes_file_patterns(root, patterns, forbidden) do
    patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(root, pattern), match_dot: true)
    end)
    |> Enum.uniq()
    |> Enum.each(fn path ->
      refute contains_forbidden_ref?(File.read!(path), forbidden),
             "#{path} still references #{forbidden}"
    end)
  end

  defp contains_forbidden_ref?(contents, "Mezzanine." <> _rest = forbidden) do
    contents
    |> String.split(forbidden)
    |> Enum.drop(1)
    |> Enum.any?(fn
      "" -> true
      rest -> rest |> :binary.first() |> namespace_boundary?()
    end)
  end

  defp contains_forbidden_ref?(contents, forbidden), do: String.contains?(contents, forbidden)

  defp namespace_boundary?(byte),
    do: not (byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte == ?_)

  defp assert_refutes_normalized_file_patterns(root, patterns, forbidden) do
    patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(Path.join(root, pattern), match_dot: true)
    end)
    |> Enum.uniq()
    |> Enum.each(fn path ->
      normalized = path |> File.read!() |> String.split() |> Enum.join(" ")

      refute String.contains?(normalized, forbidden),
             "#{path} still references #{forbidden}"
    end)
  end
end
