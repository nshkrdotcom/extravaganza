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
       credential_redeemed?: true,
       provider_request_sent?: true,
       provider_response_received?: true,
       viewer_resolution: %{
         output: %{user: %{id: "usr-linear-viewer"}},
         provider_request_sent?: true,
         provider_response_received?: true,
         lower_request_ref: "lower-request://fixture/linear/viewer",
         lower_receipt_ref: "lower-receipt://fixture/linear/viewer"
       },
       lower_request_ref: "lower-request://fixture/linear/current-states",
       lower_receipt_ref: "lower-receipt://fixture/linear/current-states"
     }}
  end

  @impl true
  def fetch_linear_candidates(_context, source_binding, opts) do
    source_binding_id = Map.get(source_binding, :source_binding_id, "linear-primary")
    subjects = fixture_linear_subjects(source_binding) |> filter_fixture_subjects(source_binding)
    page_subjects = page_fixture_subjects(subjects, opts)

    {:ok,
     %{
       source_binding_id: source_binding_id,
       credential_redeemed?: true,
       provider_request_sent?: true,
       provider_response_received?: true,
       source_intake: %{
         operation: "linear.issues.list",
         source_binding_id: source_binding_id,
         subject_attrs: page_subjects,
         page_info: %{
           has_next_page: length(page_subjects) < length(subjects),
           end_cursor: if(length(page_subjects) < length(subjects), do: "fixture-cursor-1")
         }
       },
       viewer_resolution: %{
         output: %{user: %{id: "usr-linear-viewer"}},
         provider_request_sent?: true,
         provider_response_received?: true,
         lower_request_ref: "lower-request://fixture/linear/viewer",
         lower_receipt_ref: "lower-receipt://fixture/linear/viewer"
       },
       lower_request_ref: "lower-request://fixture/linear/source",
       lower_receipt_ref: "lower-receipt://fixture/linear/source"
     }}
  end

  @impl true
  def publish_linear_source(_context, attrs, opts) do
    source_binding_id = Map.get(attrs, :source_binding_id, "linear-primary")
    receipt = fixture_publication_receipt(source_binding_id, attrs, opts)
    denied? = Map.get(receipt, :status) in ["dry_run_denied", "denied"]

    {:ok,
     %{
       credential_redeemed?: true,
       provider_request_sent?: not denied?,
       provider_response_received?: not denied?,
       lower_denial_ref: Map.get(receipt, :lower_denial_ref),
       source_publication_receipt: receipt
     }}
  end

  @impl true
  def execute_linear_graphql_tool(_context, _attrs, _opts) do
    output = ~s({"data":{"viewer":{"id":"usr-linear-viewer"}}})

    {:ok,
     %{
       operation: "linear.graphql.execute",
       tool_name: "linear_graphql",
       success?: true,
       dynamic_tool_response: %{
         "success" => true,
         "output" => output,
         "contentItems" => [
           %{
             "type" => "inputText",
             "text" => output
           }
         ]
       },
       lower_request_ref: "lower-request://fixture/linear/graphql",
       lower_receipt_ref: "lower-receipt://fixture/linear/graphql/succeeded",
       provider_request_sent?: true,
       provider_response_received?: true,
       credential_redeemed?: true
     }}
  end

  defp fixture_publication_receipt(source_binding_id, attrs, opts) do
    base = %{
      source_publication_receipt_ref: "source-publication://#{source_binding_id}/fixture",
      source_publish_ref: Map.get(attrs, :source_publish_ref, "source-publish://fixture"),
      source_binding_id: source_binding_id,
      source_ref: Map.get(attrs, :source_ref, "linear://fixture/issue/ENG-321"),
      status: "published"
    }

    cond do
      Keyword.get(opts, :dry_run?) == true ->
        base
        |> Map.delete(:source_publication_receipt_ref)
        |> Map.merge(%{
          source_publication_denial_ref:
            "lower-denial://fixture/linear/publication-dry-run/policy_denied",
          status: "dry_run_denied",
          capability_id: fixture_publication_capability(attrs),
          issue_id: Map.get(attrs, :issue_id),
          lower_request_ref: "lower-request://fixture/linear/publication-dry-run",
          lower_denial_ref: "lower-denial://fixture/linear/publication-dry-run/policy_denied",
          denial_class: "policy_denied",
          denial_reason: "dry run requested before provider dispatch",
          provider_request_sent?: false,
          provider_response_received?: false,
          workpad_refs: []
        })

      Map.get(attrs, :state_id) || Map.get(attrs, :state_name) ->
        Map.merge(base, %{
          capability_id: "linear.issues.update",
          issue_id: Map.get(attrs, :issue_id),
          state_id: Map.get(attrs, :state_id, "state-fixture-done"),
          state_name: Map.get(attrs, :state_name),
          lower_request_ref: "lower-request://fixture/linear/state-update",
          lower_receipt_ref: "lower-receipt://fixture/linear/state-update",
          workpad_refs: []
        })

      Map.get(attrs, :comment_id) ->
        comment_ref = "linear-comment://#{Map.fetch!(attrs, :comment_id)}"

        Map.merge(base, %{
          capability_id: "linear.comments.update",
          lower_request_ref: "lower-request://fixture/linear/publication-update",
          lower_receipt_ref: "lower-receipt://fixture/linear/publication-update",
          comment_ref: comment_ref,
          workpad_refs: [comment_ref]
        })

      true ->
        Map.merge(base, %{
          capability_id: "linear.comments.create",
          lower_request_ref: "lower-request://fixture/linear/publication",
          lower_receipt_ref: "lower-receipt://fixture/linear/publication",
          comment_ref: "linear-comment://fixture/comment-1",
          workpad_refs: ["linear-comment://fixture/comment-1"]
        })
    end
  end

  defp fixture_publication_capability(attrs) do
    cond do
      Map.get(attrs, :state_id) || Map.get(attrs, :state_name) -> "linear.issues.update"
      Map.get(attrs, :comment_id) -> "linear.comments.update"
      true -> "linear.comments.create"
    end
  end

  defp fixture_linear_subjects(source_binding) do
    source_binding_id = Map.get(source_binding, :source_binding_id, "linear-primary")

    [
      %{
        source_ref: "linear://fixture/issue/ENG-321",
        source_id: "ENG-321",
        provider: "linear",
        provider_external_ref: "lin-issue-321",
        provider_revision: "2026-03-12T10:00:00Z",
        source_binding_id: source_binding_id,
        title: "Investigate rollback",
        description: "The deployment rolled back after the health checks failed.",
        priority: 2,
        labels: ["automation", "incident"],
        branch_ref: "eng-321-investigate-rollback",
        source_url: "https://linear.app/acme/issue/ENG-321",
        source_state: "Todo",
        workflow_state: "Todo",
        blocker_refs: [
          %{
            "provider" => "linear",
            "relation_type" => "blocks",
            "direction" => "inbound",
            "provider_external_ref" => "lin-issue-009",
            "identifier" => "SEC-9",
            "source_ref" => "linear://issue/SEC-9",
            "source_state" => "In Progress",
            "title" => "Restore deployment credentials",
            "url" => "https://linear.app/acme/issue/SEC-9"
          }
        ],
        source_routing: %{
          "assignee" => %{"id" => "usr-linear-viewer", "name" => "Taylor Automation"},
          "project" => %{"id" => "project-ops", "slug_id" => "ENG", "name" => "Engineering"},
          "team" => %{"id" => "team-eng", "key" => "ENG", "name" => "Engineering"}
        },
        opened_at: "2026-03-12T09:15:00Z"
      }
    ]
  end

  defp filter_fixture_subjects(subjects, source_binding) do
    filters = map_value(source_binding, :candidate_filters) || %{}
    state_names = filters |> value(:state_names) |> List.wrap() |> Enum.reject(&is_nil/1)
    project_slug = value(filters, :project_slug)
    team_id = value(filters, :team_id)

    Enum.filter(subjects, fn subject ->
      state_match?(subject, state_names) and project_match?(subject, project_slug) and
        team_match?(subject, team_id)
    end)
  end

  defp state_match?(_subject, []), do: true

  defp state_match?(subject, state_names) do
    normalized_states = MapSet.new(Enum.map(state_names, &normalize_string/1))
    MapSet.member?(normalized_states, normalize_string(value(subject, :source_state)))
  end

  defp project_match?(_subject, nil), do: true

  defp project_match?(subject, project_slug) do
    project = subject |> value(:source_routing) |> map_value(:project)

    normalize_string(value(project, :slug_id) || value(project, :name)) ==
      normalize_string(project_slug)
  end

  defp team_match?(_subject, nil), do: true

  defp team_match?(subject, team_id) do
    team = subject |> value(:source_routing) |> map_value(:team)
    value(team, :id) == team_id
  end

  defp page_fixture_subjects(subjects, opts) do
    case positive_integer(value(opts, :first) || value(opts, :page_size)) do
      nil -> subjects
      first -> Enum.take(subjects, first)
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> nil
    end
  end

  defp positive_integer(_value), do: nil

  defp map_value(attrs, key), do: if(is_map(value(attrs, key)), do: value(attrs, key), else: nil)

  defp value(%{} = attrs, key) when is_atom(key),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp value(_attrs, _key), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(_value), do: ""

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
