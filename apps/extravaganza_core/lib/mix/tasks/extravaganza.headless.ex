defmodule Mix.Tasks.Extravaganza.Headless.TaskSupport do
  @moduledoc false

  @live_operations [
    :live_linear_source,
    :live_linear_current_states,
    :live_codex_turn,
    :live_linear_publication,
    :live_linear_graphql_tool,
    :live_github_evidence,
    :live_smoke
  ]
  @no_start_operations [
    :profile,
    :profile_validate
  ]
  @live_surface_dependency_apps [
    :jido_integration_v2_control_plane,
    :req
  ]

  @spec run(atom(), [String.t()]) :: :ok
  def run(operation, argv) when is_atom(operation) and is_list(argv) do
    configure_json_logging(argv)

    if start_app?(operation, argv) do
      Mix.Task.run("app.start")
    end

    case maybe_start_live_surface_dependencies(operation, argv) do
      :ok ->
        Extravaganza.HeadlessCLI.run(operation, argv)

      {:error, reason} ->
        emit_startup_error(reason, argv)
    end
  end

  defp maybe_start_live_surface_dependencies(operation, argv) do
    if live_surface_dependencies_required?(operation, argv),
      do: start_live_surface_dependencies(),
      else: :ok
  end

  defp live_surface_dependencies_required?(operation, argv),
    do: operation in @live_operations and "--live-product-path" in argv

  defp start_live_surface_dependencies do
    Enum.reduce_while(@live_surface_dependency_apps, :ok, fn app, :ok ->
      case Application.ensure_all_started(app) do
        {:ok, _apps} -> {:cont, :ok}
        {:error, {:already_started, _app}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:live_surface_dependency_failed, app, reason}}}
      end
    end)
  end

  defp render_startup_error({:live_surface_dependency_failed, app, reason}) do
    %{
      ok: false,
      schema: "extravaganza.headless.response.v1",
      operation: "startup",
      error: %{
        code: "live_surface_dependency_failed",
        app: app,
        reason: inspect(reason)
      }
    }
  end

  defp render_startup_error(reason) do
    %{
      ok: false,
      schema: "extravaganza.headless.response.v1",
      operation: "startup",
      error: %{code: "startup_failed", reason: inspect(reason)}
    }
  end

  defp emit_startup_error(reason, argv) do
    payload = render_startup_error(reason)

    if "--json" in argv do
      IO.puts(Jason.encode!(payload))
    else
      Mix.shell().error(payload.error.reason)
    end
  end

  @doc false
  def start_app?(operation, argv) do
    cond do
      "--fixture" in argv -> false
      operation in @no_start_operations -> false
      operation in @live_operations -> false
      true -> true
    end
  end

  defp configure_json_logging(argv) do
    if "--json" in argv do
      Application.put_env(:logger, :level, :error)
      :logger.set_primary_config(:level, :error)
      Logger.configure(level: :error)
    end
  end
end

defmodule Mix.Tasks.Extravaganza.Headless.State do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless state JSON"
  def run(argv), do: TaskSupport.run(:state, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Queue do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless queue JSON"
  def run(argv), do: TaskSupport.run(:queue, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Subject do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless subject detail JSON"
  def run(argv), do: TaskSupport.run(:subject, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Run do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless run detail JSON"
  def run(argv), do: TaskSupport.run(:run, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Start do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Start a headless run"
  def run(argv), do: TaskSupport.run(:start, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Refresh do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Request a headless refresh"
  def run(argv), do: TaskSupport.run(:refresh, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Control do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Send a headless control command"
  def run(argv), do: TaskSupport.run(:control, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Reviews do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print pending headless reviews"
  def run(argv), do: TaskSupport.run(:reviews, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Review do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Record a headless review decision"
  def run(argv), do: TaskSupport.run(:review, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.SourcePreview do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print source publication preview"
  def run(argv), do: TaskSupport.run(:source_preview, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Source.Sync do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Sync a deterministic Linear-shaped source page"
  def run(argv), do: TaskSupport.run(:source_sync, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.SourceSync do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Sync a deterministic Linear-shaped source page"
  def run(argv), do: TaskSupport.run(:source_sync, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.SourcePublish do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Publish a governed Linear source update"
  def run(argv), do: TaskSupport.run(:source_publish, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Profile do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print imported Symphony workflow profile JSON"
  def run(argv), do: TaskSupport.run(:profile, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.ProfileReload do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Reload an imported Symphony workflow profile"
  def run(argv), do: TaskSupport.run(:profile_reload, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.ProfileValidate do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Validate an imported Symphony workflow profile"
  def run(argv), do: TaskSupport.run(:profile_validate, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Status do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless runtime status JSON"
  def run(argv), do: TaskSupport.run(:status, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Logs do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless runtime logs JSON"
  def run(argv), do: TaskSupport.run(:logs, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.LinearSource do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear source example"
  def run(argv), do: TaskSupport.run(:live_linear_source, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveLinearSource do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear source example"
  def run(argv), do: TaskSupport.run(:live_linear_source, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.LinearCurrentStates do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear current-state example"
  def run(argv), do: TaskSupport.run(:live_linear_current_states, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveLinearCurrentStates do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear current-state example"
  def run(argv), do: TaskSupport.run(:live_linear_current_states, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.CodexTurn do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Codex turn example"
  def run(argv), do: TaskSupport.run(:live_codex_turn, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveCodexTurn do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Codex turn example"
  def run(argv), do: TaskSupport.run(:live_codex_turn, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.LinearPublication do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear publication example"
  def run(argv), do: TaskSupport.run(:live_linear_publication, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveLinearPublication do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear publication example"
  def run(argv), do: TaskSupport.run(:live_linear_publication, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.LinearGraphqlTool do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear GraphQL dynamic tool example"
  def run(argv), do: TaskSupport.run(:live_linear_graphql_tool, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveLinearGraphqlTool do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear GraphQL dynamic tool example"
  def run(argv), do: TaskSupport.run(:live_linear_graphql_tool, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.GithubEvidence do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated GitHub evidence example"
  def run(argv), do: TaskSupport.run(:live_github_evidence, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveGithubEvidence do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated GitHub evidence example"
  def run(argv), do: TaskSupport.run(:live_github_evidence, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Live.Smoke do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the aggregate live-gated headless smoke"
  def run(argv), do: TaskSupport.run(:live_smoke, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.LiveSmoke do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the aggregate live-gated headless smoke"
  def run(argv), do: TaskSupport.run(:live_smoke, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Evidence do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless evidence chain"
  def run(argv), do: TaskSupport.run(:evidence, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Events do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Print headless event page"
  def run(argv), do: TaskSupport.run(:events, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Smoke do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the deterministic headless smoke"
  def run(argv), do: TaskSupport.run(:smoke, argv)
end
