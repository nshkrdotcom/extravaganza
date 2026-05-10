defmodule Extravaganza.HeadlessCLI do
  @moduledoc """
  Product-owned command dispatcher for local headless examples and Mix tasks.
  """

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    EventPresenter,
    EvidencePresenter,
    ReviewPresenter,
    RunPresenter,
    StatePresenter,
    SubjectPresenter
  }

  alias Extravaganza.{HeadlessFixtureBackend, HeadlessJSON, HeadlessSurface, ProductHost}

  @operations [
    :state,
    :queue,
    :subject,
    :run,
    :start,
    :refresh,
    :control,
    :reviews,
    :review,
    :source_preview,
    :evidence,
    :events,
    :smoke
  ]

  @spec operations() :: [atom()]
  def operations, do: @operations

  @spec run(atom(), [String.t()]) :: :ok
  def run(operation, argv) when operation in @operations and is_list(argv) do
    opts = parse(argv)
    maybe_install_fixture_backend(opts)

    operation
    |> dispatch(opts)
    |> print_envelope(operation, opts)
  end

  defp dispatch(:state, opts),
    do:
      HeadlessJSON.wrap(
        :state,
        HeadlessSurface.state_snapshot(%{}, []),
        &StatePresenter.present/1,
        opts
      )

  defp dispatch(:queue, opts) do
    case HeadlessSurface.operator_queue(%{}, []) do
      {:ok, queue} -> HeadlessJSON.success(:queue, StatePresenter.present_queue(queue), opts)
      {:error, reason} -> HeadlessJSON.error(:queue, reason, opts)
    end
  end

  defp dispatch(:subject, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :subject,
      HeadlessSurface.subject_detail(subject_id, %{}, []),
      &SubjectPresenter.present/1,
      opts
    )
  end

  defp dispatch(:run, opts) do
    run_id = positional(opts, 0) || Map.get(opts, :run_id) || "run:fixture"

    HeadlessJSON.wrap(
      :run,
      HeadlessSurface.run_detail(run_id, %{}, []),
      &RunPresenter.present/1,
      opts
    )
  end

  defp dispatch(:start, opts) do
    if Map.has_key?(opts, :fixture) do
      dispatch(:run, Map.put(opts, :operation_override, :start))
    else
      HeadlessJSON.wrap(
        :start,
        ProductHost.start_run(default_linear_subject(opts), product_opts(opts)),
        &present_start_result/1,
        opts
      )
    end
  end

  defp dispatch(:refresh, opts) do
    attrs = %{"idempotency_key" => Map.get(opts, :idempotency_key) || "idem:headless-refresh"}

    HeadlessJSON.wrap(
      :refresh,
      HeadlessSurface.request_refresh(attrs, []),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:control, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"
    action = Map.get(opts, :action) || positional(opts, 1) || "retry"
    attrs = %{"idempotency_key" => Map.get(opts, :idempotency_key) || "idem:headless-control"}

    HeadlessJSON.wrap(
      :control,
      HeadlessSurface.request_control(subject_id, action, attrs, []),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:reviews, opts),
    do:
      HeadlessJSON.wrap(
        :reviews,
        HeadlessSurface.list_reviews(%{}, []),
        &ReviewPresenter.present_page/1,
        opts
      )

  defp dispatch(:review, opts) do
    decision_id = positional(opts, 0) || Map.get(opts, :decision_id) || "decision:fixture"
    decision = Map.get(opts, :decision) || "accept"

    identity = %{
      id: decision_id,
      decision_kind: "operator_review",
      subject_id: Map.get(opts, :subject_id) || "subject:fixture",
      subject_kind: "linear_issue"
    }

    attrs = %{
      "decision" => decision,
      "reason" => Map.get(opts, :reason) || "headless fixture decision"
    }

    HeadlessJSON.wrap(
      :review,
      HeadlessSurface.record_review_decision(identity, attrs, []),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:source_preview, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :source_preview,
      HeadlessSurface.source_publication_preview(subject_id, []),
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:evidence, opts) do
    run_id = positional(opts, 0) || Map.get(opts, :run_id) || "run:fixture"

    HeadlessJSON.wrap(
      :evidence,
      HeadlessSurface.evidence_chain(run_id, %{}, []),
      &EvidencePresenter.present/1,
      opts
    )
  end

  defp dispatch(:events, opts) do
    run_id = Map.get(opts, :run_id) || positional(opts, 0) || "run:fixture"

    HeadlessJSON.wrap(
      :events,
      HeadlessSurface.events(%{"run_id" => run_id}, []),
      &EventPresenter.present_page/1,
      opts
    )
  end

  defp dispatch(:smoke, %{deterministic?: true, same_run?: true} = opts) do
    HeadlessJSON.wrap(:smoke, ProductHost.same_run_smoke(opts), fn value -> value end, opts)
  end

  defp dispatch(:smoke, opts) do
    results = %{
      "state" => dispatch(:state, opts),
      "run" => dispatch(:run, opts),
      "evidence" => dispatch(:evidence, opts),
      "events" => dispatch(:events, opts),
      "refresh" => dispatch(:refresh, opts)
    }

    if Enum.all?(results, fn {_key, value} -> value["ok"] == true end) do
      HeadlessJSON.success(:smoke, results, opts)
    else
      HeadlessJSON.error(:smoke, :unavailable, opts)
    end
  end

  defp print_envelope(envelope, _operation, opts) do
    envelope =
      case Map.get(opts, :operation_override) do
        nil -> envelope
        override -> %{envelope | "operation" => Atom.to_string(override)}
      end

    IO.puts(Jason.encode!(envelope, pretty: Map.get(opts, :pretty?, true)))
    :ok
  end

  defp parse(argv), do: parse(argv, %{positionals: []})

  defp parse([], opts), do: opts
  defp parse(["--json" | rest], opts), do: parse(rest, opts)
  defp parse(["--pretty" | rest], opts), do: parse(rest, Map.put(opts, :pretty?, true))

  defp parse(["--fixture", fixture | rest], opts),
    do: parse(rest, Map.put(opts, :fixture, fixture))

  defp parse(["--trace-id", trace_id | rest], opts),
    do: parse(rest, Map.put(opts, :trace_id, trace_id))

  defp parse(["--tenant-id", tenant_id | rest], opts),
    do: parse(rest, Map.put(opts, :tenant_id, tenant_id))

  defp parse(["--pack-version", pack_version | rest], opts),
    do: parse(rest, Map.put(opts, :pack_version, pack_version))

  defp parse(["--run", run_id | rest], opts), do: parse(rest, Map.put(opts, :run_id, run_id))
  defp parse(["--run-id", run_id | rest], opts), do: parse(rest, Map.put(opts, :run_id, run_id))

  defp parse(["--subject", subject_id | rest], opts),
    do: parse(rest, Map.put(opts, :subject_id, subject_id))

  defp parse(["--subject-id", subject_id | rest], opts),
    do: parse(rest, Map.put(opts, :subject_id, subject_id))

  defp parse(["--issue-id", issue_id | rest], opts),
    do: parse(rest, Map.put(opts, :issue_id, issue_id))

  defp parse(["--title", title | rest], opts), do: parse(rest, Map.put(opts, :title, title))

  defp parse(["--description", description | rest], opts),
    do: parse(rest, Map.put(opts, :description, description))

  defp parse(["--action", action | rest], opts), do: parse(rest, Map.put(opts, :action, action))

  defp parse(["--decision", decision | rest], opts),
    do: parse(rest, Map.put(opts, :decision, decision))

  defp parse(["--reason", reason | rest], opts), do: parse(rest, Map.put(opts, :reason, reason))

  defp parse(["--deterministic" | rest], opts),
    do: parse(rest, Map.put(opts, :deterministic?, true))

  defp parse(["--same-run" | rest], opts), do: parse(rest, Map.put(opts, :same_run?, true))

  defp parse([value | rest], opts) do
    parse(rest, Map.update!(opts, :positionals, &(&1 ++ [value])))
  end

  defp maybe_install_fixture_backend(%{fixture: _fixture}) do
    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)
  end

  defp maybe_install_fixture_backend(_opts), do: :ok

  defp positional(opts, index), do: opts |> Map.get(:positionals, []) |> Enum.at(index)

  defp product_opts(opts) do
    unique = unique_suffix()

    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Map.put_new(:tenant_id, "extravaganza-headless-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-headless.#{unique}")
    |> Enum.to_list()
  end

  defp default_linear_subject(opts) do
    issue_id = Map.get(opts, :issue_id) || "HEADLESS-#{unique_suffix()}"
    title = Map.get(opts, :title) || "Headless deterministic start #{issue_id}"
    description = Map.get(opts, :description) || "Admitted by the headless product command path."

    %{
      external_ref: "linear:#{issue_id}",
      title: title,
      description: description,
      source_kind: "linear",
      payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo"
      },
      normalized_payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo",
        "labels" => ["headless", "deterministic"]
      }
    }
  end

  defp present_start_result(result) do
    data = HeadlessJSON.sanitize(result)
    payload = Map.get(data, "payload", %{})
    run_ref = Map.get(payload, "run_ref", %{})
    subject_ref = Map.get(run_ref, "subject_ref", %{})
    metadata = Map.get(run_ref, "metadata", %{})

    %{
      "surface" => Map.get(data, "surface"),
      "state" => Map.get(data, "state"),
      "subject_ref" => ref_id(subject_ref) || Map.get(payload, "work_object_id"),
      "run_ref" => run_ref_id(run_ref),
      "workflow_ref" => Map.get(payload, "workflow_start_ref"),
      "workflow_dispatch_state" => Map.get(payload, "workflow_dispatch_state"),
      "runtime_profile_ref" => get_in(payload, ["run_request_metadata", "runtime_profile_ref"]),
      "lower_runtime_kind" => get_in(payload, ["run_request_metadata", "lower_runtime_kind"]),
      "idempotency_key" => Map.get(metadata, "idempotency_key"),
      "review_required" => Map.get(payload, "review_required"),
      "review_unit_id" => Map.get(payload, "review_unit_id")
    }
  end

  defp ref_id(%{"id" => id}) when is_binary(id), do: id
  defp ref_id(_value), do: nil

  defp run_ref_id(%{"id" => id}) when is_binary(id), do: id
  defp run_ref_id(%{"run_id" => run_id}) when is_binary(run_id), do: run_id
  defp run_ref_id(_value), do: nil

  defp unique_suffix do
    "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
  end
end
