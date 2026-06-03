defmodule Extravaganza.ChassisRegistration do
  @moduledoc """
  Registers Extravaganza with Chassis through AppKit.SpatialGateway.

  This child runs after ProductBootstrap in the `:rest_for_one` application
  supervisor. A standalone SpatialGateway backend is allowed to keep legacy
  local boot behavior; all other registration errors stop this child.
  """

  use GenServer

  alias AppKit.SpatialGateway
  alias Extravaganza.ProductBootstrap

  require Logger

  @type state :: %{
          app_atom: atom(),
          git_sha: String.t(),
          profile_ref: String.t(),
          receipt_ref: String.t() | nil,
          standalone: boolean()
        }

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    case register(opts) do
      {:ok, %{standalone: true} = state} ->
        Logger.info("Chassis not available; Extravaganza running standalone")
        {:ok, state}

      {:ok, %{receipt_ref: receipt_ref} = state} ->
        Logger.info("Extravaganza registered with Chassis (#{receipt_ref})")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Chassis registration failed: #{inspect(reason)}")
        {:stop, {:chassis_registration_failed, reason}}
    end
  end

  @spec register(keyword()) :: {:ok, state()} | {:error, term()}
  def register(opts \\ []) when is_list(opts) do
    app_atom = Keyword.get(opts, :app_atom, :extravaganza)
    git_sha = Keyword.get(opts, :release_sha) || read_release_sha()

    with {:ok, profile_ref} <- SpatialGateway.get_active_profile(opts) do
      register_opts =
        Keyword.merge(opts,
          installation_ref: bootstrap_installation_ref(opts),
          tenant_ref: bootstrap_tenant_ref(opts),
          profile_ref: profile_ref,
          environment: read_environment(opts),
          release_version: read_release_version()
        )

      case SpatialGateway.register_deployed_app(app_atom, git_sha, register_opts) do
        {:ok, receipt_ref} ->
          {:ok,
           %{
             app_atom: app_atom,
             git_sha: git_sha,
             profile_ref: profile_ref,
             receipt_ref: receipt_ref,
             standalone: false
           }}

        {:error, reason} when reason in [:standalone, :registry_unavailable] ->
          {:ok,
           %{
             app_atom: app_atom,
             git_sha: git_sha,
             profile_ref: profile_ref,
             receipt_ref: nil,
             standalone: true
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp read_release_sha do
    path = Application.app_dir(:extravaganza_core, "priv/release_sha.txt")

    case File.read(path) do
      {:ok, sha} -> String.trim(sha)
      _ -> Application.get_env(:extravaganza_core, :release_sha, "unknown")
    end
  end

  defp read_release_version do
    :extravaganza_core
    |> Application.spec(:vsn)
    |> to_string()
  end

  defp read_environment(opts) do
    case Keyword.get(opts, :environment) ||
           Application.get_env(:extravaganza_core, :chassis_env, :dev) do
      :prod -> :prod
      "prod" -> :prod
      _ -> :dev
    end
  end

  defp bootstrap_installation_ref(opts) do
    case Keyword.get(opts, :installation_ref) || ProductBootstrap.cached_installation_ref() do
      {:ok, ref} -> ref
      ref when is_binary(ref) -> ref
      _ -> "installation:local:default"
    end
  end

  defp bootstrap_tenant_ref(opts) do
    Keyword.get(opts, :tenant_ref) ||
      Application.get_env(:extravaganza_core, :tenant_ref, "tenant:local")
  end
end
