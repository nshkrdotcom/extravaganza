defmodule Extravaganza.HeadlessFixtureBackend do
  @moduledoc """
  Deterministic local backend for product-owned headless examples.

  This is a fixture lane for scripts and smoke examples. It implements the
  AppKit headless backend contract so examples still enter through AppKit DTOs.
  """

  @behaviour AppKit.Core.Backends.HeadlessBackend

  alias AppKit.Core.RuntimeReadback.{
    CommandResult,
    RuntimeRunDetail,
    RuntimeStateSnapshot,
    RuntimeSubjectDetail
  }

  @source_fixture_root Path.expand("../../test/fixtures/headless_m1", __DIR__)

  @impl true
  def state_snapshot(context, _request, _opts) do
    "state_snapshot.json"
    |> fixture()
    |> put_context(context)
    |> RuntimeStateSnapshot.new()
  end

  @impl true
  def runtime_subject_detail(_context, subject_ref, _request, _opts) do
    "subject_detail.json"
    |> fixture()
    |> Map.put("subject_ref", to_string(subject_ref))
    |> RuntimeSubjectDetail.new()
  end

  @impl true
  def runtime_run_detail(_context, run_ref, _request, _opts) do
    "run_detail.json"
    |> fixture()
    |> Map.put("run_ref", to_string(run_ref))
    |> RuntimeRunDetail.new()
  end

  @impl true
  def request_runtime_refresh(_context, request, _opts) do
    "command_result.json"
    |> fixture()
    |> Map.merge(%{
      "command_kind" => "refresh",
      "idempotency_key" => request.idempotency_key,
      "correlation_id" => "corr:fixture-refresh"
    })
    |> CommandResult.new()
  end

  @impl true
  def request_runtime_control(_context, request, _opts) do
    fixture_name =
      if request.params["deny"] == "true", do: "command_denied.json", else: "command_result.json"

    fixture_name
    |> fixture()
    |> Map.merge(%{
      "command_kind" => to_string(request.action),
      "idempotency_key" => request.idempotency_key,
      "correlation_id" => "corr:fixture-control"
    })
    |> CommandResult.new()
  end

  defp fixture(name) do
    name
    |> fixture_path()
    |> File.read!()
    |> Jason.decode!()
  end

  defp fixture_path(name) do
    priv_path = Application.app_dir(:extravaganza_core, Path.join("priv/headless_m1", name))

    cond do
      File.regular?(priv_path) ->
        priv_path

      File.regular?(Path.join(@source_fixture_root, name)) ->
        Path.join(@source_fixture_root, name)

      true ->
        priv_path
    end
  end

  defp put_context(attrs, context) do
    attrs
    |> Map.put("tenant_ref", context_ref(context, :tenant_ref, "tenant:fixture"))
    |> Map.put(
      "installation_ref",
      context_ref(context, :installation_ref, "installation:fixture")
    )
  end

  defp context_ref(context, key, default) do
    value = Map.get(context, key)

    cond do
      is_binary(value) -> value
      is_map(value) && Map.has_key?(value, :id) -> Map.fetch!(value, :id)
      is_map(value) && Map.has_key?(value, "id") -> Map.fetch!(value, "id")
      true -> default
    end
  end
end
