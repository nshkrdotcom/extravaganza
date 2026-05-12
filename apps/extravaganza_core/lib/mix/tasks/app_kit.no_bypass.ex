defmodule Mix.Tasks.AppKit.NoBypass do
  @moduledoc """
  Runs the AppKit product-boundary no-bypass scanner for this umbrella.
  """

  use Mix.Task

  @shortdoc "Scan Extravaganza product files for AppKit boundary bypasses"

  @default_includes [
    "apps/extravaganza_core/lib/**/*.ex",
    "apps/extravaganza_web/lib/**/*.ex"
  ]

  @impl true
  def run(argv) do
    repo_root = repo_root()
    args = argv |> normalize_root_args(File.cwd!()) |> ensure_root(repo_root) |> ensure_includes()

    Mix.Task.reenable("cmd")
    Mix.Task.run("cmd", ["--cd", app_kit_path(repo_root), "mix", "app_kit.no_bypass.scan" | args])
  end

  defp normalize_root_args(["--root", root | rest], cwd) do
    ["--root", Path.expand(root, cwd) | normalize_root_args(rest, cwd)]
  end

  defp normalize_root_args(["-r", root | rest], cwd) do
    ["-r", Path.expand(root, cwd) | normalize_root_args(rest, cwd)]
  end

  defp normalize_root_args([<<"--root=", root::binary>> | rest], cwd) do
    ["--root=#{Path.expand(root, cwd)}" | normalize_root_args(rest, cwd)]
  end

  defp normalize_root_args([arg | rest], cwd), do: [arg | normalize_root_args(rest, cwd)]
  defp normalize_root_args([], _cwd), do: []

  defp ensure_root(args, repo_root) do
    if has_root?(args), do: args, else: ["--root", repo_root | args]
  end

  defp has_root?(args) do
    Enum.any?(args, &(&1 == "--root" or &1 == "-r" or String.starts_with?(&1, "--root=")))
  end

  defp ensure_includes(args) do
    if has_include?(args) do
      args
    else
      args ++ Enum.flat_map(@default_includes, &["--include", &1])
    end
  end

  defp has_include?(args) do
    Enum.any?(args, &(&1 == "--include" or String.starts_with?(&1, "--include=")))
  end

  defp repo_root do
    __DIR__
    |> Path.expand()
    |> Path.join("../../../../..")
    |> Path.expand()
  end

  defp app_kit_path(repo_root), do: Path.expand("../app_kit", repo_root)
end
