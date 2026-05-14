defmodule Extravaganza.HeadlessPreflightTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend, HeadlessPreflight}

  setup do
    previous_headless_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)

    on_exit(fn ->
      restore_env(:app_kit_core, :headless_backend, previous_headless_backend)
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
    end)
  end

  test "preflight report covers app db temporal backend source and credential refs" do
    assert {:ok, report} =
             HeadlessPreflight.run(
               app_start_result: {:ok, [:extravaganza_core]},
               db_repos: [__MODULE__.StartedStore, __MODULE__.SecondStartedStore],
               started_repos: [__MODULE__.StartedStore, __MODULE__.SecondStartedStore],
               temporal_status: "reachable",
               backend_opts: [
                 backend: HeadlessFixtureBackend,
                 source_backend: HeadlessFixtureBackend
               ],
               source_binding_refs: ["linear_primary", "linear_secondary"],
               credential_refs: ["LINEAR_API_KEY", "GH_TOKEN"]
             )

    assert report["schema_ref"] == "headless_dependency_preflight.v1"
    assert report["replacement_for"] == "symphony_startup_dependency_preflight"
    assert report["overall_status"] == "ok"

    checks = report["checks"]
    assert checks["application"]["status"] == "started"
    assert checks["application"]["app"] == "extravaganza_core"
    assert "extravaganza_core" in checks["application"]["started_apps"]

    assert checks["db"]["status"] == "started"

    repos_by_name = Map.new(checks["db"]["repos"], &{&1["module"], &1})
    assert repos_by_name["Extravaganza.HeadlessPreflightTest.StartedStore"]["status"] == "started"

    assert repos_by_name["Extravaganza.HeadlessPreflightTest.SecondStartedStore"]["status"] ==
             "started"

    assert checks["temporal_substrate"]["status"] == "reachable"
    assert checks["temporal_substrate"]["repo_ref"] == "repo://mezzanine"
    assert checks["temporal_substrate"]["status_command"] == "just dev-status"
    assert "just dev-up" in checks["temporal_substrate"]["allowed_commands"]
    assert checks["temporal_substrate"]["raw_temporal_commands_allowed?"] == false

    backends_by_surface = Map.new(report["app_kit_backends"], &{&1["surface"], &1})
    assert backends_by_surface["headless"]["backend"] == "Extravaganza.HeadlessFixtureBackend"
    assert backends_by_surface["runtime"]["backend"] == "Extravaganza.HeadlessFixtureBackend"
    assert backends_by_surface["source"]["backend"] == "Extravaganza.HeadlessFixtureBackend"

    assert Enum.map(report["source_bindings"], & &1["ref"]) == [
             "linear_primary",
             "linear_secondary"
           ]

    assert Enum.map(report["credential_refs"], & &1["ref"]) == ["LINEAR_API_KEY", "GH_TOKEN"]
    assert report["credential_policy"]["ambient_os_env_read?"] == false
    assert report["credential_policy"]["secret_values_redacted?"] == true

    encoded = Jason.encode!(report)
    refute encoded =~ "temporal server start-dev"
    refute encoded =~ "linear-api-secret"
  end

  test "temporal substrate failure is returned as standard product JSON" do
    assert {:error, {:temporal_substrate_unavailable, report}} =
             HeadlessPreflight.run(
               app_start_result: {:ok, [:extravaganza_core]},
               db_repos: [],
               temporal_status: "unavailable"
             )

    assert report["overall_status"] == "failed"
    assert get_in(report, ["checks", "temporal_substrate", "status"]) == "unavailable"
  end

  test "CLI preflight emits a standard envelope without reading or printing secret material" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:preflight, [
                   "--json",
                   "--skip-app-start",
                   "--temporal-status",
                   "reachable",
                   "--source-binding-ref",
                   "linear_primary",
                   "--credential-refs",
                   "LINEAR_API_KEY,GH_TOKEN"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "preflight"
    assert decoded["data"]["schema_ref"] == "headless_dependency_preflight.v1"
    assert get_in(decoded, ["data", "checks", "application", "status"]) == "skipped"
    assert get_in(decoded, ["data", "checks", "temporal_substrate", "status"]) == "reachable"
    assert get_in(decoded, ["data", "credential_policy", "ambient_os_env_read?"]) == false

    refute output =~ "temporal server start-dev"
    refute output =~ "linear-api-secret"
    refute output =~ "/home/"
  end

  defmodule StartedStore do
  end

  defmodule SecondStartedStore do
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
