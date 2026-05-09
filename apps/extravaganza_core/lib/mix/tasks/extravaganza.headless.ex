defmodule Mix.Tasks.Extravaganza.Headless.State do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless state JSON"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:state, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Queue do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless queue JSON"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:queue, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Subject do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless subject detail JSON"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:subject, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Run do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless run detail JSON"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:run, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Start do
  use Mix.Task

  @moduledoc false
  @shortdoc "Start a headless fixture run"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:start, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Refresh do
  use Mix.Task

  @moduledoc false
  @shortdoc "Request a headless refresh"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:refresh, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Control do
  use Mix.Task

  @moduledoc false
  @shortdoc "Send a headless control command"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:control, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Reviews do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print pending headless reviews"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:reviews, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Review do
  use Mix.Task

  @moduledoc false
  @shortdoc "Record a headless review decision"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:review, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.SourcePreview do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print source publication preview"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:source_preview, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Evidence do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless evidence chain"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:evidence, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Events do
  use Mix.Task

  @moduledoc false
  @shortdoc "Print headless event page"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:events, argv)
end

defmodule Mix.Tasks.Extravaganza.Headless.Smoke do
  use Mix.Task

  @moduledoc false
  @shortdoc "Run the deterministic headless smoke"
  def run(argv), do: Extravaganza.HeadlessCLI.run(:smoke, argv)
end
