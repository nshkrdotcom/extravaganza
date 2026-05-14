defmodule ExtravaganzaWeb.HeadlessServerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias ExtravaganzaWeb.HeadlessServer
  alias Mix.Tasks.Extravaganza.Headless.Web

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
end
