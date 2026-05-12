defmodule Extravaganza.HeadlessFixtureBackend do
  @moduledoc """
  Deterministic local backend for product-owned headless examples.

  This is a fixture lane for scripts and smoke examples. It implements the
  AppKit headless backend contract so examples still enter through AppKit DTOs.
  """

  @behaviour AppKit.Core.Backends.HeadlessBackend
  @behaviour AppKit.Core.Backends.SourceBackend

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

  @impl true
  def sync_linear_issues(_context, source_page, _opts) do
    {:ok,
     %{
       source_binding_id: Map.get(source_page, :source_binding_id, "linear-primary"),
       synced_issue_count: 1,
       subject_refs: ["subject:fixture"],
       lower_request_ref: "lower-request://fixture/linear/source-sync",
       lower_receipt_ref: "lower-receipt://fixture/linear/source-sync"
     }}
  end

  @impl true
  def current_linear_issue_states(_context, issue_ids, _source_binding, _opts) do
    {:ok,
     %{
       requested_issue_ids: issue_ids,
       states: Enum.into(issue_ids, %{}, &{&1, "Todo"}),
       missing_issue_ids: [],
       lower_request_ref: "lower-request://fixture/linear/current-states",
       lower_receipt_ref: "lower-receipt://fixture/linear/current-states"
     }}
  end

  @impl true
  def fetch_linear_candidates(_context, source_binding, _opts) do
    source_binding_id = Map.get(source_binding, :source_binding_id, "linear-primary")

    {:ok,
     %{
       source_binding_id: source_binding_id,
       credential_redeemed?: true,
       provider_request_sent?: true,
       provider_response_received?: true,
       source_intake: %{
         operation: "linear.issues.list",
         subject_attrs: [
           %{
             source_ref: "linear://fixture/issue/ENG-321",
             source_id: "ENG-321",
             title: "Investigate rollback",
             workflow_state: "Todo"
           }
         ]
       },
       lower_request_ref: "lower-request://fixture/linear/source",
       lower_receipt_ref: "lower-receipt://fixture/linear/source"
     }}
  end

  @impl true
  def publish_linear_source(_context, attrs, _opts) do
    source_binding_id = Map.get(attrs, :source_binding_id, "linear-primary")

    {:ok,
     %{
       credential_redeemed?: true,
       provider_request_sent?: true,
       provider_response_received?: true,
       source_publication_receipt: %{
         source_publication_receipt_ref: "source-publication://#{source_binding_id}/fixture",
         source_publish_ref: Map.get(attrs, :source_publish_ref, "source-publish://fixture"),
         source_binding_id: source_binding_id,
         source_ref: Map.get(attrs, :source_ref, "linear://fixture/issue/ENG-321"),
         status: "published",
         capability_id: "linear.comments.create",
         lower_request_ref: "lower-request://fixture/linear/publication",
         lower_receipt_ref: "lower-receipt://fixture/linear/publication",
         workpad_refs: ["linear-comment://fixture/comment-1"]
       }
     }}
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
