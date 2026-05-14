defmodule ExtravaganzaWeb.HeadlessServer do
  @moduledoc """
  Product-owned optional HTTP shell for headless operator surfaces.

  This replaces Symphony's optional `--port` / `server.port` HTTP extension with
  an Extravaganza web command that resolves the port from explicit caller input
  or a caller-supplied workflow profile. It does not read ambient OS
  environment variables.
  """

  alias Extravaganza.SymphonyWorkflowImport
  alias ExtravaganzaWeb.Endpoint

  @default_host "127.0.0.1"
  @route_map %{
    "GET /operator-console" => "open http://127.0.0.1:PORT/operator-console",
    "GET /api/v1/state" => "mix extravaganza.headless.state --json",
    "GET /api/v1/status" => "mix extravaganza.headless.status --json",
    "GET /api/v1/preflight" => "mix extravaganza.headless.preflight --json",
    "GET /api/v1/logs" => "mix extravaganza.headless.logs --json",
    "GET /api/v1/events" => "mix extravaganza.headless.events --json --run run:fixture",
    "GET /api/v1/:issue_identifier" => "curl http://127.0.0.1:PORT/api/v1/:issue_identifier",
    "POST /api/v1/refresh" => "mix extravaganza.headless.refresh --json",
    "POST /api/v1/source-publication" =>
      "mix extravaganza.headless.source_publish SUBJECT_ID --json"
  }

  @type plan :: map()

  @spec child_spec(keyword() | map()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(keyword() | map()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    with {:ok, plan} <- plan(opts) do
      if plan["enabled?"] do
        configure_endpoint!(plan)
        Endpoint.start_link()
      else
        :ignore
      end
    end
  end

  @spec bound_port() :: non_neg_integer() | nil
  def bound_port do
    case Bandit.PhoenixAdapter.server_info(Endpoint, :http) do
      {:ok, {_ip, port}} when is_integer(port) -> port
      _other -> nil
    end
  rescue
    _error -> nil
  catch
    :exit, _reason -> nil
  end

  @spec plan(keyword() | map()) :: {:ok, plan()} | {:error, term()}
  def plan(opts \\ []) do
    opts = normalize_opts(opts)

    with {:ok, profile} <- workflow_profile(opts),
         {:ok, port, port_source} <- resolve_port(opts, profile),
         {:ok, host} <- resolve_host(opts, profile),
         {:ok, ip} <- parse_host(host) do
      workflow_port = workflow_server_port(profile)

      {:ok,
       %{
         "replacement_for" => "symphony_http_server_extension",
         "enabled?" => is_integer(port),
         "configured_port" => port,
         "workflow_server_port" => workflow_port,
         "port_source" => port_source,
         "host" => host,
         "bind_host" => format_host(ip),
         "ephemeral_port_requested?" => port == 0,
         "endpoint_module" => inspect(Endpoint),
         "service_lifecycle" => service_lifecycle(),
         "supervision_equivalence" => supervision_equivalence(),
         "start_command" => start_command(port),
         "route_map" => @route_map
       }}
    end
  end

  @spec configure_endpoint!(plan()) :: :ok
  def configure_endpoint!(%{"configured_port" => port, "host" => host} = _plan)
      when is_integer(port) do
    {:ok, ip} = parse_host(host)

    existing = Application.get_env(:extravaganza_web, Endpoint, [])

    updated =
      existing
      |> Keyword.put(:server, true)
      |> Keyword.put(:http, Keyword.merge(Keyword.get(existing, :http, []), ip: ip, port: port))
      |> Keyword.put(:url, Keyword.merge(Keyword.get(existing, :url, []), host: host, port: port))

    Application.put_env(:extravaganza_web, Endpoint, updated)
    :ok
  end

  def configure_endpoint!(_plan), do: :ok

  defp normalize_opts(opts) when is_list(opts), do: Keyword.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)

  defp workflow_profile(opts) do
    if workflow_profile_requested?(opts) do
      opts
      |> Keyword.take([:workflow_path, :workflow, :cwd, :env, :profile_cache_path])
      |> SymphonyWorkflowImport.profile()
    else
      {:ok, nil}
    end
  end

  defp workflow_profile_requested?(opts) do
    Enum.any?([:workflow_path, :workflow, :cwd], &Keyword.has_key?(opts, &1))
  end

  defp resolve_port(opts, profile) do
    cond do
      Keyword.has_key?(opts, :port) ->
        validate_port(Keyword.fetch!(opts, :port), "cli_port")

      is_integer(workflow_server_port(profile)) ->
        validate_port(workflow_server_port(profile), "workflow_server_port")

      true ->
        {:ok, nil, nil}
    end
  end

  defp validate_port(port, source) when is_integer(port) and port >= 0, do: {:ok, port, source}
  defp validate_port(port, _source), do: {:error, {:invalid_port, port}}

  defp resolve_host(opts, profile) do
    host =
      cond do
        Keyword.has_key?(opts, :host) -> Keyword.fetch!(opts, :host)
        workflow_server_host(profile) not in [nil, ""] -> workflow_server_host(profile)
        true -> @default_host
      end

    if is_binary(host) and String.trim(host) != "" do
      {:ok, String.trim(host)}
    else
      {:error, {:invalid_host, host}}
    end
  end

  defp workflow_server_port(nil), do: nil
  defp workflow_server_port(profile), do: get_in(profile, ["config", "server", "port"])

  defp workflow_server_host(nil), do: nil
  defp workflow_server_host(profile), do: get_in(profile, ["config", "server", "host"])

  defp parse_host(@default_host), do: {:ok, {127, 0, 0, 1}}
  defp parse_host("localhost"), do: {:ok, {127, 0, 0, 1}}

  defp parse_host(host) when is_binary(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> {:error, {:invalid_host, host}}
    end
  end

  defp format_host({127, 0, 0, 1}), do: @default_host
  defp format_host(ip), do: ip |> :inet.ntoa() |> to_string()

  defp service_lifecycle do
    %{
      "mode" => "long_running_phoenix_shell",
      "replacement_for" => "symphony_cli_wait_for_shutdown",
      "one_shot?" => false,
      "start_module" => inspect(__MODULE__),
      "supervisor" => inspect(Endpoint),
      "waits_for_shutdown?" => true
    }
  end

  defp supervision_equivalence do
    [
      %{
        "symphony_child" => "Phoenix.PubSub",
        "symphony_role" => "broadcast dashboard and observability updates",
        "classification" => "product_owned",
        "replacement_owner" => "ExtravaganzaWeb",
        "replacement_surfaces" => ["ExtravaganzaWeb.PubSub"],
        "product_exposure" => ["/operator-console", "/api/v1/events", "/api/v1/status"],
        "evidence" =>
          "ExtravaganzaWeb.Application supervises Phoenix.PubSub as ExtravaganzaWeb.PubSub.",
        "status" => "closed",
        "remaining_gap_refs" => []
      },
      %{
        "symphony_child" => "Task.Supervisor",
        "symphony_role" => "supervise per-issue asynchronous worker tasks",
        "classification" => "delegated_and_product_exposed",
        "replacement_owner" => "AppKit and Mezzanine runtime surfaces",
        "replacement_surfaces" => [
          "AppKit runtime surface",
          "AppKit work surface",
          "Mezzanine workflow runtime"
        ],
        "product_exposure" => [
          "mix extravaganza.headless.start",
          "mix extravaganza.headless.status",
          "mix extravaganza.headless.logs",
          "mix extravaganza.headless.stop",
          "/api/v1/status",
          "/api/v1/logs"
        ],
        "evidence" =>
          "Extravaganza observes and controls worker execution through AppKit/ProductHost DTOs.",
        "status" => "delegated_and_exposed",
        "remaining_gap_refs" => []
      },
      %{
        "symphony_child" => "SymphonyElixir.WorkflowStore",
        "symphony_role" => "cache and reload the active workflow configuration",
        "classification" => "product_owned",
        "replacement_owner" => "ExtravaganzaCore",
        "replacement_surfaces" => [
          "Extravaganza.SymphonyWorkflowImport",
          "profile_cache_path",
          "mix extravaganza.headless.reload"
        ],
        "product_exposure" => [
          "mix extravaganza.headless.profile",
          "mix extravaganza.headless.reload",
          "mix extravaganza.headless.status",
          "/api/v1/profile/reload",
          "/api/v1/status"
        ],
        "evidence" =>
          "Workflow profile parsing, cache reload, reload status, and future starts are product-owned.",
        "status" => "closed",
        "remaining_gap_refs" => []
      },
      %{
        "symphony_child" => "SymphonyElixir.Orchestrator",
        "symphony_role" => "own polling, dispatch, retries, runtime state, and refresh",
        "classification" => "delegated_and_product_exposed",
        "replacement_owner" => "AppKit and Mezzanine runtime surfaces",
        "replacement_surfaces" => [
          "AppKit runtime surface",
          "AppKit work surface",
          "Mezzanine workflow runtime"
        ],
        "product_exposure" => [
          "mix extravaganza.headless.start",
          "mix extravaganza.headless.status",
          "mix extravaganza.headless.refresh",
          "mix extravaganza.headless.stop",
          "/api/v1/status",
          "/api/v1/refresh"
        ],
        "evidence" =>
          "Extravaganza uses AppKit/ProductHost commands and readbacks for runtime lifecycle control.",
        "status" => "delegated_and_exposed",
        "remaining_gap_refs" => []
      },
      %{
        "symphony_child" => "SymphonyElixir.HttpServer",
        "symphony_role" => "start the optional HTTP observability endpoint",
        "classification" => "product_owned",
        "replacement_owner" => "ExtravaganzaWeb",
        "replacement_surfaces" => [
          "ExtravaganzaWeb.HeadlessServer",
          "ExtravaganzaWeb.Endpoint",
          "mix extravaganza.headless.web"
        ],
        "product_exposure" => [
          "mix extravaganza.headless.web",
          "/operator-console",
          "/api/v1/state",
          "/api/v1/status",
          "/api/v1/refresh",
          "/api/v1/source-publication"
        ],
        "evidence" =>
          "HeadlessServer configures and starts ExtravaganzaWeb.Endpoint for the headless shell.",
        "status" => "closed",
        "remaining_gap_refs" => []
      },
      %{
        "symphony_child" => "SymphonyElixir.StatusDashboard",
        "symphony_role" => "render terminal and browser status from orchestrator snapshots",
        "classification" => "product_owned_with_follow_up",
        "replacement_owner" => "ExtravaganzaWeb and AppKit operator surfaces",
        "replacement_surfaces" => [
          "ExtravaganzaWeb operator console",
          "ExtravaganzaWeb API readbacks",
          "AppKit operator surface"
        ],
        "product_exposure" => [
          "/operator-console",
          "/api/v1/state",
          "/api/v1/status",
          "/api/v1/events",
          "/api/v1/logs"
        ],
        "evidence" =>
          "Operator console and API readbacks expose status; offline shutdown rendering remains separate.",
        "status" => "mapped_with_shutdown_offline_follow_up",
        "remaining_gap_refs" => ["META-SVC-004"]
      }
    ]
  end

  defp start_command(nil), do: "mix extravaganza.headless.web --port PORT --json"
  defp start_command(port), do: "mix extravaganza.headless.web --port #{port} --json"
end
