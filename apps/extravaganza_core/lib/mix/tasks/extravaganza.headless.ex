defmodule Mix.Tasks.Extravaganza.Headless.TaskSupport do
  @moduledoc false

  @spec run(atom(), [String.t()]) :: :ok
  def run(operation, argv) when is_atom(operation) and is_list(argv) do
    unless fixture_args?(argv) do
      configure_json_logging(argv)
      Mix.Task.run("app.start")
    end

    Extravaganza.HeadlessCLI.run(operation, argv)
  end

  defp fixture_args?(argv), do: "--fixture" in argv

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

defmodule Mix.Tasks.Extravaganza.Headless.Live.LinearSource do
  use Mix.Task

  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @moduledoc false
  @shortdoc "Run the live-gated Linear source example"
  def run(argv), do: TaskSupport.run(:live_linear_source, argv)
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
