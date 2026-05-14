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
    "GET /api/v1/logs" => "mix extravaganza.headless.logs --json",
    "GET /api/v1/events" => "mix extravaganza.headless.events --json --run run:fixture",
    "GET /api/v1/:issue_identifier" => "curl http://127.0.0.1:PORT/api/v1/:issue_identifier",
    "POST /api/v1/refresh" => "mix extravaganza.headless.refresh --json"
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

  defp start_command(nil), do: "mix extravaganza.headless.web --port PORT --json"
  defp start_command(port), do: "mix extravaganza.headless.web --port #{port} --json"
end
