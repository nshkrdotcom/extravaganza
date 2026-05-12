defmodule Extravaganza.HeadlessRuntimeSurfaceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AppKit.Core.RuntimeSurface.{
    LiveEffectReceipt,
    RuntimeLogPage,
    RuntimeProfileApplyResult,
    RuntimeStatusSnapshot
  }

  alias Extravaganza.{HeadlessCLI, HeadlessSurface}

  @secret "linear-secret-value"

  setup do
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.RuntimeBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  @tag :tmp_dir
  test "profile reload applies the imported runtime profile through AppKit", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "last-good-profile.json")

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_reload, [
                   "--json",
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-apply"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "profile_reload"
    assert decoded["data"]["status"] == "reloaded"
    assert decoded["data"]["runtime_profile_apply"]["status"] == "updated"

    assert decoded["data"]["runtime_profile_apply"]["profile_ref"] ==
             "runtime-profile://symphony-workflow"

    assert decoded["runtime_profile_ref"] == "runtime-profile://symphony-workflow"
    refute output =~ @secret
  end

  test "status and logs commands read through AppKit runtime surface" do
    for {operation, schema_ref} <- [
          {:status, "headless_runtime_status.v1"},
          {:logs, "headless_runtime_logs.v1"}
        ] do
      output =
        capture_io(fn ->
          assert :ok = HeadlessCLI.run(operation, ["--json", "--trace-id", "trace:runtime"])
        end)

      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["operation"] == Atom.to_string(operation)
      assert decoded["data"]["schema_ref"] == schema_ref

      case operation do
        :status ->
          assert decoded["data"]["data"]["tenant_ref"] == "extravaganza"

        :logs ->
          assert get_in(decoded, [
                   "data",
                   "data",
                   "entries",
                   Access.at(0),
                   "payload",
                   "tenant_ref"
                 ]) ==
                   "extravaganza"
      end
    end
  end

  test "source_publish command delegates to AppKit source surface" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:source_publish, [
                   "--json",
                   "--subject",
                   "subject:fixture",
                   "--trace-id",
                   "trace:source-publish"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "source_publish"
    assert decoded["data"]["schema_ref"] == "headless_source_publication.v1"
    assert decoded["data"]["data"]["status"] == "receipt_recorded"
    assert decoded["refs"]["source_publication_ref"] == "source-publication:fixture"
  end

  test "HeadlessSurface exposes runtime status logs and source publication wrappers" do
    assert {:ok, status} = HeadlessSurface.runtime_status(%{}, [])
    assert status.health == %{"runtime" => "ok"}

    assert {:ok, logs} = HeadlessSurface.runtime_logs(%{}, [])
    assert [%{event_kind: "runtime_profile_applied"}] = logs.entries

    assert {:ok, published} =
             HeadlessSurface.publish_linear_source(%{
               subject_ref: "subject:fixture",
               effect: "comment"
             })

    assert published["source_publication_receipt_ref"] == "source-publication:fixture"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp write_workflow!(tmp_dir) do
    path = Path.join(tmp_dir, "WORKFLOW.md")

    File.write!(path, """
    ---
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: ENG
    codex:
      command: codex app-server
    ---
    Ship {{ issue.identifier }}
    """)

    path
  end

  defmodule RuntimeBackend do
    @behaviour AppKit.Core.Backends.RuntimeBackend

    @impl true
    def apply_runtime_profile(context, runtime_profile, _opts) do
      RuntimeProfileApplyResult.new(%{
        status: :updated,
        tenant_ref: context.tenant_ref.id,
        profile_ref: "runtime-profile://symphony-workflow",
        program_ref: "program://#{get_in(runtime_profile, ["program", "slug"])}",
        policy_bundle_ref: "policy-bundle://symphony-workflow",
        work_class_ref: "work-class://symphony-workflow",
        placement_profile_ref: "placement-profile://symphony-workflow-local",
        metadata: %{"source" => "runtime-backend-test"}
      })
    end

    @impl true
    def runtime_status(context, _request, _opts) do
      RuntimeStatusSnapshot.new(%{
        tenant_ref: context.tenant_ref.id,
        program_ref: "program://symphony-workflow",
        health: %{"runtime" => "ok"},
        preflight: %{"linear" => "credential_present"},
        metadata: %{"source" => "runtime-backend-test"}
      })
    end

    @impl true
    def runtime_logs(context, _request, _opts) do
      RuntimeLogPage.new(%{
        entries: [
          %{
            ref: "runtime-log:fixture:1",
            event_kind: "runtime_profile_applied",
            occurred_at: "2026-05-11T00:00:00Z",
            summary: "Runtime profile applied",
            payload: %{"tenant_ref" => context.tenant_ref.id}
          }
        ],
        total_count: 1,
        has_more?: false
      })
    end

    @impl true
    def record_live_effect(context, attrs, _opts) do
      LiveEffectReceipt.new(
        Map.merge(attrs, %{
          tenant_ref: context.tenant_ref.id,
          provider: "linear",
          effect: "comment",
          status: :receipt_recorded
        })
      )
    end

    @impl true
    def fetch_github_pr_evidence(_context, _request, _opts), do: {:error, :not_used}
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_linear_issues(_context, _source_page, _opts), do: {:ok, %{}}

    @impl true
    def current_linear_issue_states(_context, _issue_ids, _source_binding, _opts),
      do: {:ok, %{}}

    @impl true
    def fetch_linear_candidates(_context, source_binding, _opts) do
      {:ok,
       %{
         source_binding_id: Map.get(source_binding, :source_binding_id) || "linear-primary",
         source_intake: %{operation: "linear.issues.list", subject_attrs: []},
         provider_request_sent?: true,
         provider_response_received?: true
       }}
    end

    @impl true
    def publish_linear_source(context, attrs, _opts) do
      {:ok,
       %{
         "source_publication_receipt_ref" => "source-publication:fixture",
         "tenant_ref" => context.tenant_ref.id,
         "subject_ref" => Map.get(attrs, :subject_ref) || Map.get(attrs, "subject_ref"),
         "status" => "receipt_recorded",
         "provider" => "linear",
         "effect" => Map.get(attrs, :effect) || Map.get(attrs, "effect") || "comment"
       }}
    end
  end
end
