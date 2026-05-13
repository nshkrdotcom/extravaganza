defmodule Extravaganza.TestSupport.FakeHeadlessBackend do
  @moduledoc false

  @behaviour AppKit.Core.Backends.HeadlessBackend

  alias AppKit.Core.RuntimeReadback.{
    CommandResult,
    RuntimeRunDetail,
    RuntimeStateSnapshot,
    RuntimeSubjectDetail
  }

  @fixture_root Path.expand("../fixtures/headless_m1", __DIR__)

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
    send(self(), {:headless_refresh_request, request})

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
    @fixture_root
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
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
