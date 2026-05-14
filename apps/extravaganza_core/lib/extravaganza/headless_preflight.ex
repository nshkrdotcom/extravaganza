defmodule Extravaganza.HeadlessPreflight do
  @moduledoc """
  Product-owned dependency preflight for the headless command and API surface.
  """

  alias AppKit.BackendConfig
  alias Extravaganza.{Config, ProductPack}

  @schema_ref "headless_dependency_preflight.v1"
  @replacement_for "symphony_startup_dependency_preflight"
  @app :extravaganza_core
  @compiled_default_backend :compiled_app_kit_surface_default
  @allowed_substrate_commands [
    "just dev-up",
    "just dev-status",
    "just dev-logs",
    "just temporal-ui"
  ]
  @default_credential_refs [
    "LINEAR_API_KEY",
    "OPENAI_API_KEY",
    "CODEX_API_KEY",
    "GH_TOKEN",
    "GITHUB_TOKEN"
  ]

  @backend_surfaces [
    %{surface: "headless", explicit_key: :backend, app_env_key: :headless_backend},
    %{surface: "runtime", explicit_key: :backend, app_env_key: :runtime_backend},
    %{surface: "source", explicit_key: :source_backend, app_env_key: :source_backend}
  ]

  @type preflight_result :: {:ok, map()} | {:error, {atom(), map()}}

  @spec run(keyword() | map()) :: preflight_result()
  def run(opts \\ []) when is_list(opts) or is_map(opts) do
    opts = opts_map(opts)
    report = report(opts)

    case failure_reason(report) do
      nil -> {:ok, report}
      reason -> {:error, {reason, report}}
    end
  end

  defp report(opts) do
    application = application_check(opts)
    db = db_check(opts)
    temporal = temporal_substrate_check(opts)

    %{
      "schema_ref" => @schema_ref,
      "replacement_for" => @replacement_for,
      "overall_status" => overall_status([application, db, temporal]),
      "checks" => %{
        "application" => application,
        "db" => db,
        "temporal_substrate" => temporal
      },
      "app_kit_backends" => backend_checks(opts),
      "source_bindings" => source_binding_checks(opts),
      "credential_refs" => credential_ref_checks(opts),
      "credential_policy" => credential_policy(),
      "generated_by" => "Extravaganza.HeadlessPreflight"
    }
  end

  defp application_check(opts) do
    cond do
      truthy?(opt(opts, :skip_app_start?, ["skip_app_start?", "skip_app_start"])) ->
        %{
          "status" => "skipped",
          "app" => Atom.to_string(@app),
          "start_attempted?" => false,
          "reason" => "caller_requested_skip"
        }

      Map.has_key?(opts, :app_start_result) ->
        present_app_start_result(Map.fetch!(opts, :app_start_result))

      true ->
        @app
        |> safe_ensure_all_started()
        |> present_app_start_result()
    end
  end

  defp present_app_start_result({:ok, apps}) when is_list(apps) do
    %{
      "status" => "started",
      "app" => Atom.to_string(@app),
      "start_attempted?" => true,
      "started_apps" => Enum.map(apps, &Atom.to_string/1)
    }
  end

  defp present_app_start_result({:error, reason}) do
    %{
      "status" => "failed",
      "app" => Atom.to_string(@app),
      "start_attempted?" => true,
      "reason" => inspect(reason)
    }
  end

  defp present_app_start_result(other) do
    %{
      "status" => "failed",
      "app" => Atom.to_string(@app),
      "start_attempted?" => true,
      "reason" => inspect(other)
    }
  end

  defp safe_ensure_all_started(app) do
    Application.ensure_all_started(app)
  rescue
    error -> {:error, {error.__struct__, Exception.message(error)}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp db_check(opts) do
    if truthy?(opt(opts, :skip_app_start?, ["skip_app_start?", "skip_app_start"])) do
      skipped_db_check()
    else
      started_db_check(opts)
    end
  end

  defp skipped_db_check do
    %{
      "status" => "skipped",
      "configured_repo_count" => 0,
      "repos" => [],
      "reason" => "app_start_skipped"
    }
  end

  defp started_db_check(opts) do
    repos = db_repos(opts)
    started_repos = MapSet.new(List.wrap(opt(opts, :started_repos, ["started_repos"])))
    rows = Enum.map(repos, &repo_check(&1, started_repos))

    %{
      "status" => db_status(rows),
      "configured_repo_count" => length(rows),
      "repos" => rows
    }
  end

  defp repo_check(repo, started_repos) do
    started? =
      if MapSet.size(started_repos) > 0,
        do: MapSet.member?(started_repos, repo),
        else: repo_started?(repo)

    %{
      "module" => module_name(repo),
      "status" => if(started?, do: "started", else: "not_started")
    }
  end

  defp db_repos(opts) do
    opts
    |> opt(:db_repos, ["db_repos"])
    |> case do
      nil -> Application.get_env(@app, :ecto_repos, [])
      repos -> List.wrap(repos)
    end
    |> Enum.uniq()
  end

  defp db_status([]), do: "not_configured"

  defp db_status(rows) do
    if Enum.all?(rows, &(&1["status"] == "started")), do: "started", else: "failed"
  end

  defp repo_started?(repo) when is_atom(repo), do: is_pid(Process.whereis(repo))
  defp repo_started?(_repo), do: false

  defp temporal_substrate_check(opts) do
    status =
      opts
      |> opt(:temporal_status, ["temporal_status", "temporal-status"])
      |> normalize_temporal_status()

    %{
      "status" => status,
      "repo_ref" => "repo://mezzanine",
      "runtime_substrate" => "mezzanine",
      "status_command" => "just dev-status",
      "allowed_commands" => @allowed_substrate_commands,
      "raw_temporal_commands_allowed?" => false,
      "status_source" => temporal_status_source(opts)
    }
  end

  defp normalize_temporal_status(value) when value in ["ok", "ready", "reachable"],
    do: "reachable"

  defp normalize_temporal_status(value) when value in ["failed", "down", "unavailable"],
    do: "unavailable"

  defp normalize_temporal_status(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_temporal_status()

  defp normalize_temporal_status(value) when is_binary(value), do: value
  defp normalize_temporal_status(_value), do: "not_checked"

  defp temporal_status_source(opts) do
    if present?(opt(opts, :temporal_status, ["temporal_status", "temporal-status"])),
      do: "caller_supplied_status",
      else: "not_supplied"
  end

  defp backend_checks(opts) do
    backend_opts = opt(opts, :backend_opts, ["backend_opts"]) || []

    Enum.map(@backend_surfaces, fn spec ->
      backend =
        BackendConfig.resolve(
          backend_opts,
          spec.explicit_key,
          spec.app_env_key,
          @compiled_default_backend
        )

      %{
        "surface" => spec.surface,
        "status" => "resolved",
        "backend" => module_name(backend),
        "app_env_key" => Atom.to_string(spec.app_env_key),
        "resolution_source" => backend_resolution_source(backend_opts, spec)
      }
    end)
  end

  defp backend_resolution_source(backend_opts, spec) do
    cond do
      Keyword.has_key?(backend_opts, spec.explicit_key) -> "explicit_opts"
      present?(Application.get_env(:app_kit_core, spec.app_env_key)) -> "app_env"
      true -> "compiled_surface_default"
    end
  end

  defp source_binding_checks(opts) do
    opts
    |> list_opt(:source_binding_refs, [
      "source_binding_refs",
      "source-binding-refs",
      :source_binding_ref,
      "source_binding_ref",
      "source-binding-ref"
    ])
    |> default_list(default_source_binding_refs())
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      %{
        "ref" => ref,
        "status" => "declared",
        "source" => "product_pack_or_caller"
      }
    end)
  end

  defp credential_ref_checks(opts) do
    opts
    |> list_opt(:credential_refs, [
      "credential_refs",
      "credential-refs",
      :credential_ref,
      "credential_ref",
      "credential-ref"
    ])
    |> default_list(@default_credential_refs)
    |> Enum.uniq()
    |> Enum.map(fn ref ->
      %{
        "ref" => ref,
        "status" => "ref_only",
        "secret_material_checked?" => false
      }
    end)
  end

  defp credential_policy do
    %{
      "ambient_os_env_read?" => false,
      "secret_values_redacted?" => true,
      "workstation_wrapper" => "~/scripts/with_bash_secrets",
      "accepted_ingress" => [
        "shell_env_for_live_command",
        "credential_ref",
        "credential_lease_ref"
      ]
    }
  end

  defp default_source_binding_refs do
    [ProductPack.source_binding_key(Config.load())]
  rescue
    _error -> ["linear_primary"]
  catch
    _kind, _reason -> ["linear_primary"]
  end

  defp overall_status(checks) do
    if Enum.any?(checks, &failed_check?/1), do: "failed", else: "ok"
  end

  defp failure_reason(%{"checks" => %{"application" => %{"status" => "failed"}}}),
    do: :app_not_started

  defp failure_reason(%{"checks" => %{"db" => %{"status" => "failed"}}}), do: :app_not_started

  defp failure_reason(%{"checks" => %{"temporal_substrate" => %{"status" => status}}})
       when status in ["unavailable", "failed"],
       do: :temporal_substrate_unavailable

  defp failure_reason(_report), do: nil

  defp failed_check?(%{"status" => status}), do: status in ["failed", "unavailable"]
  defp failed_check?(_check), do: false

  defp list_opt(opts, key, aliases) do
    [opt(opts, key, aliases) | Enum.map(aliases, &Map.get(opts, &1))]
    |> Enum.flat_map(&split_list/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_list(nil), do: []
  defp split_list(value) when is_list(value), do: Enum.flat_map(value, &split_list/1)
  defp split_list(value) when is_atom(value), do: [Atom.to_string(value)]

  defp split_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp split_list(value), do: [to_string(value)]

  defp default_list([], defaults), do: defaults
  defp default_list(values, _defaults), do: values

  defp opts_map(opts) when is_map(opts), do: opts
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp opt(opts, key, aliases) do
    Enum.find_value([key | aliases], fn candidate ->
      value = Map.get(opts, candidate)
      if is_nil(value), do: nil, else: value
    end)
  end

  defp module_name(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> inspect(module)
      atom_name -> atom_name
    end
  end

  defp module_name(value), do: to_string(value)

  defp present?(value), do: value not in [nil, ""]
  defp truthy?(value), do: value in [true, "true", "1", 1]
end
