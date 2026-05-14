defmodule Mix.Tasks.Extravaganza.Headless.Specs.Check do
  use Mix.Task

  alias Extravaganza.HeadlessSpecCheck

  @moduledoc """
  Enforces adjacent `@spec` declarations for the headless public surface.
  """

  @shortdoc "Fails when headless public functions are missing @specs"

  @switches [path: :keep, exemptions_file: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("invalid options for extravaganza.headless.specs.check: #{inspect(invalid)}")
    end

    paths = selected_paths(opts)
    exemptions = selected_exemptions(opts)
    findings = HeadlessSpecCheck.missing_public_specs(paths, exemptions: exemptions)

    if findings == [] do
      Mix.shell().info("extravaganza.headless.specs.check: all headless public functions pass")
      :ok
    else
      Enum.each(findings, fn finding ->
        Mix.shell().error(HeadlessSpecCheck.format_finding(finding))
      end)

      Mix.raise(
        "extravaganza.headless.specs.check failed with #{length(findings)} missing @spec declaration(s)"
      )
    end
  end

  defp selected_paths(opts) do
    case Keyword.get_values(opts, :path) do
      [] -> HeadlessSpecCheck.default_paths()
      paths -> paths
    end
  end

  defp selected_exemptions(opts) do
    case Keyword.get(opts, :exemptions_file) do
      nil -> HeadlessSpecCheck.default_exemptions()
      path -> HeadlessSpecCheck.load_exemptions(path)
    end
  end
end
