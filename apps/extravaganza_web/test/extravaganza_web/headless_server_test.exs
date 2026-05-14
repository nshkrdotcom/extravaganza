defmodule ExtravaganzaWeb.HeadlessServerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.TestSupport.FakeHeadlessBackend
  alias ExtravaganzaWeb.HeadlessServer
  alias Mix.Tasks.Extravaganza.Headless.Web

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :headless_backend, FakeHeadlessBackend)
    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.RuntimeBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      restore_env(:app_kit_core, :headless_backend, previous_backend)
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  @tag :tmp_dir
  test "CLI port overrides workflow server port and keeps route mappings explicit", %{
    tmp_dir: tmp_dir
  } do
    workflow_path = write_workflow!(tmp_dir, port: 4242, host: "127.0.0.1")

    assert {:ok, plan} =
             HeadlessServer.plan(
               port: 0,
               workflow_path: workflow_path,
               env: %{}
             )

    assert plan["replacement_for"] == "symphony_http_server_extension"
    assert plan["enabled?"] == true
    assert plan["configured_port"] == 0
    assert plan["workflow_server_port"] == 4242
    assert plan["port_source"] == "cli_port"
    assert plan["host"] == "127.0.0.1"
    assert plan["bind_host"] == "127.0.0.1"
    assert plan["ephemeral_port_requested?"] == true
    assert plan["endpoint_module"] == "ExtravaganzaWeb.Endpoint"

    assert plan["route_map"]["GET /api/v1/state"] ==
             "mix extravaganza.headless.state --json"

    assert plan["route_map"]["GET /api/v1/:issue_identifier"] ==
             "curl http://127.0.0.1:PORT/api/v1/:issue_identifier"

    assert plan["route_map"]["GET /operator-console"] ==
             "open http://127.0.0.1:PORT/operator-console"

    assert plan["route_map"]["POST /api/v1/source-publication"] ==
             "mix extravaganza.headless.source_publish SUBJECT_ID --json"
  end

  @tag :tmp_dir
  test "workflow server port enables the web shell when CLI port is absent", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir, port: 5057, host: "127.0.0.1")

    assert {:ok, plan} = HeadlessServer.plan(workflow_path: workflow_path, env: %{})

    assert plan["enabled?"] == true
    assert plan["configured_port"] == 5057
    assert plan["workflow_server_port"] == 5057
    assert plan["port_source"] == "workflow_server_port"
    assert plan["ephemeral_port_requested?"] == false
  end

  test "missing port leaves the optional web shell disabled" do
    assert {:ok, plan} = HeadlessServer.plan([])

    assert plan["enabled?"] == false
    assert plan["configured_port"] == nil
    assert plan["port_source"] == nil
    assert plan["start_command"] == "mix extravaganza.headless.web --port PORT --json"
  end

  test "invalid ports and hosts are rejected before endpoint configuration" do
    assert {:error, {:invalid_port, -1}} = HeadlessServer.plan(port: -1)
    assert {:error, {:invalid_host, "bad host"}} = HeadlessServer.plan(port: 0, host: "bad host")
  end

  test "mix task can print the resolved web plan without starting the endpoint" do
    Mix.Task.reenable("extravaganza.headless.web")

    output =
      capture_io(fn ->
        assert :ok = Web.run(["--json", "--once", "--port", "0"])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "web"
    assert decoded["data"]["enabled?"] == true
    assert decoded["data"]["configured_port"] == 0
    assert decoded["data"]["port_source"] == "cli_port"
  end

  test "long-running web shell serves readbacks and accepts operator events" do
    assert {:ok, plan} = HeadlessServer.plan(port: 0)

    assert plan["service_lifecycle"] == %{
             "mode" => "long_running_phoenix_shell",
             "replacement_for" => "symphony_cli_wait_for_shutdown",
             "one_shot?" => false,
             "start_module" => "ExtravaganzaWeb.HeadlessServer",
             "supervisor" => "ExtravaganzaWeb.Endpoint",
             "waits_for_shutdown?" => true
           }

    release_endpoint_for_headless_server()

    pid = start_supervised!({HeadlessServer, port: 0})
    port = wait_for_bound_port()
    base_url = "http://127.0.0.1:#{port}"

    assert {200, %{"ok" => true, "operation" => "state"}} =
             get_json("#{base_url}/api/v1/state")

    assert {200, %{"ok" => true, "operation" => "status"}} =
             get_json("#{base_url}/api/v1/status")

    assert {202, %{"ok" => true, "operation" => "refresh"}} =
             post_json("#{base_url}/api/v1/refresh", %{"reason" => "phase89-lifecycle"})

    assert {200, %{"ok" => true, "operation" => "source_publish"}} =
             post_json("#{base_url}/api/v1/source-publication", %{
               "subject_ref" => "subject:fixture",
               "effect" => "comment",
               "message" => "Phase 89 lifecycle source event"
             })

    assert Process.alive?(pid)
  end

  test "plan maps every Symphony supervised child to its product replacement" do
    assert {:ok, plan} = HeadlessServer.plan(port: 0)

    equivalence = plan["supervision_equivalence"]

    assert Enum.map(equivalence, & &1["symphony_child"]) == [
             "Phoenix.PubSub",
             "Task.Supervisor",
             "SymphonyElixir.WorkflowStore",
             "SymphonyElixir.Orchestrator",
             "SymphonyElixir.HttpServer",
             "SymphonyElixir.StatusDashboard"
           ]

    assert Enum.all?(equivalence, fn row ->
             is_binary(row["symphony_role"]) and
               row["classification"] in [
                 "product_owned",
                 "delegated_and_product_exposed",
                 "product_owned_with_follow_up"
               ] and
               is_binary(row["replacement_owner"]) and
               populated_list?(row["replacement_surfaces"]) and
               populated_list?(row["product_exposure"]) and
               is_binary(row["evidence"]) and
               is_binary(row["status"])
           end)

    assert row_for(equivalence, "Phoenix.PubSub")["replacement_surfaces"] == [
             "ExtravaganzaWeb.PubSub"
           ]

    assert row_for(equivalence, "Task.Supervisor")["classification"] ==
             "delegated_and_product_exposed"

    assert row_for(equivalence, "SymphonyElixir.WorkflowStore")["replacement_surfaces"] == [
             "Extravaganza.SymphonyWorkflowImport",
             "profile_cache_path",
             "mix extravaganza.headless.reload"
           ]

    assert row_for(equivalence, "SymphonyElixir.Orchestrator")["product_exposure"] == [
             "mix extravaganza.headless.start",
             "mix extravaganza.headless.status",
             "mix extravaganza.headless.refresh",
             "mix extravaganza.headless.stop",
             "/api/v1/status",
             "/api/v1/refresh"
           ]

    assert row_for(equivalence, "SymphonyElixir.HttpServer")["replacement_surfaces"] == [
             "ExtravaganzaWeb.HeadlessServer",
             "ExtravaganzaWeb.Endpoint",
             "mix extravaganza.headless.web"
           ]

    assert row_for(equivalence, "SymphonyElixir.StatusDashboard")["remaining_gap_refs"] == [
             "META-SVC-004"
           ]
  end

  defp write_workflow!(tmp_dir, opts) do
    path = Path.join(tmp_dir, "WORKFLOW.md")

    File.write!(path, """
    ---
    tracker:
      kind: memory
    server:
      port: #{Keyword.fetch!(opts, :port)}
      host: #{Keyword.fetch!(opts, :host)}
    ---
    Ship via web shell
    """)

    path
  end

  defp wait_for_bound_port(attempts \\ 20)
  defp wait_for_bound_port(0), do: flunk("headless web shell did not bind a port")

  defp wait_for_bound_port(attempts) do
    case HeadlessServer.bound_port() do
      port when is_integer(port) ->
        port

      _other ->
        Process.sleep(50)
        wait_for_bound_port(attempts - 1)
    end
  end

  defp get_json(url) do
    request_json(:get, url, nil)
  end

  defp post_json(url, body) do
    request_json(:post, url, body)
  end

  defp request_json(method, url, body) do
    :ok = ensure_inets_started()

    request =
      case method do
        :get ->
          {String.to_charlist(url), []}

        :post ->
          {String.to_charlist(url), [], ~c"application/json", Jason.encode!(body)}
      end

    {:ok, {{_version, status, _reason}, _headers, response_body}} =
      :httpc.request(method, request, [], body_format: :binary)

    {status, Jason.decode!(response_body)}
  end

  defp ensure_inets_started do
    case :inets.start() do
      :ok -> :ok
      {:error, {:already_started, :inets}} -> :ok
    end
  end

  defp release_endpoint_for_headless_server do
    case {Process.whereis(ExtravaganzaWeb.Supervisor), Process.whereis(ExtravaganzaWeb.Endpoint)} do
      {supervisor, endpoint} when is_pid(supervisor) and is_pid(endpoint) ->
        :ok = Supervisor.terminate_child(supervisor, ExtravaganzaWeb.Endpoint)
        restart_endpoint_on_exit(supervisor)

      _other ->
        :ok
    end
  end

  defp restart_endpoint_on_exit(supervisor) do
    on_exit(fn -> restart_endpoint_if_supervisor_alive(supervisor) end)
  end

  defp restart_endpoint_if_supervisor_alive(supervisor) do
    if Process.alive?(supervisor) do
      Supervisor.restart_child(supervisor, ExtravaganzaWeb.Endpoint)
    else
      :ok
    end
  end

  defp populated_list?(values) when is_list(values),
    do: values != [] and Enum.all?(values, &is_binary/1)

  defp populated_list?(_values), do: false

  defp row_for(rows, child) do
    Enum.find(rows, fn row -> row["symphony_child"] == child end) ||
      flunk("missing supervision equivalence row for #{child}")
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defmodule RuntimeBackend do
    @behaviour AppKit.Core.Backends.RuntimeBackend

    alias AppKit.Core.RuntimeSurface.{RuntimeLogPage, RuntimeStatusSnapshot}

    @impl true
    def apply_runtime_profile(_context, _runtime_profile, _opts), do: {:error, :not_used}

    @impl true
    def runtime_status(_context, _request, _opts) do
      RuntimeStatusSnapshot.new(%{
        tenant_ref: "extravaganza",
        program_ref: "program://headless-web",
        health: %{"runtime" => "ok", "web_shell" => "running"},
        preflight: %{"phoenix_endpoint" => "started"}
      })
    end

    @impl true
    def runtime_logs(_context, _request, _opts) do
      RuntimeLogPage.new(%{
        entries: [
          %{
            ref: "runtime-log:headless-web:1",
            event_kind: "headless_web.lifecycle",
            occurred_at: "2026-05-14T00:00:00Z",
            summary: "Headless web shell accepted lifecycle request",
            payload: %{"surface" => "web"}
          }
        ]
      })
    end

    @impl true
    def record_live_effect(_context, attrs, _opts), do: {:ok, attrs}

    @impl true
    def fetch_github_pr_evidence(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def cleanup_github_pr_branch(_context, _request, _opts), do: {:error, :not_used}
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_linear_issues(_context, _source_page, _opts), do: {:ok, %{}}

    @impl true
    def current_linear_issue_states(_context, _issue_ids, _source_binding, _opts),
      do: {:ok, %{}}

    @impl true
    def fetch_linear_candidates(_context, _source_binding, _opts), do: {:ok, %{}}

    @impl true
    def publish_linear_source(context, attrs, _opts) do
      {:ok,
       %{
         "source_publication_receipt_ref" => "source-publication:headless-web",
         "tenant_ref" => context.tenant_ref.id,
         "subject_ref" => Map.get(attrs, "subject_ref") || Map.get(attrs, :subject_ref),
         "status" => "receipt_recorded",
         "provider" => "linear",
         "effect" => Map.get(attrs, "effect") || Map.get(attrs, :effect)
       }}
    end

    @impl true
    def execute_linear_graphql_tool(_context, _attrs, _opts), do: {:error, :not_used}
  end
end
