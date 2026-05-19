defmodule Extravaganza.HeadlessCLI.FixtureContext do
  @moduledoc false

  alias Extravaganza.HeadlessFixtureBackend

  @spec apply(map()) :: map()
  def apply(%{fixture: _fixture} = opts) do
    opts
    |> Map.put(:headless_fixture_context?, true)
    |> Map.put_new(:skip_bootstrap?, true)
    |> Map.put_new(:headless_backend, HeadlessFixtureBackend)
    |> Map.put_new(:runtime_backend, HeadlessFixtureBackend)
    |> Map.put_new(:source_backend, HeadlessFixtureBackend)
    |> Map.put_new(:backend_stack, fixture_backend_stack())
  end

  def apply(opts) when is_map(opts), do: opts

  @spec fixture_backend_stack() :: AppKit.BackendStack.t()
  def fixture_backend_stack do
    AppKit.BackendStack.new!(%{
      headless_backend: HeadlessFixtureBackend,
      runtime_backend: HeadlessFixtureBackend,
      source_backend: HeadlessFixtureBackend
    })
  end
end
