defmodule ExtravaganzaWeb.PageControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.{ProductBootstrap, ProductHost, ProductPack, Queries, Workflows}
  alias Extravaganza.TestSupport.ExecutionTraceFixture
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Pack.Compiler

  test "GET / renders the product shell", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert String.contains?(html_response(conn, 200), "Extravaganza")
    assert String.contains?(html_response(conn, 200), "proving-ground product")
  end

  test "GET /queue renders the core-backed operator queue", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-601",
                 title: "Render operator queue",
                 description: "Drive the queue page through core",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-601"},
                 normalized_payload: %{"issue_id" => "ENG-601"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    conn = get(conn, ~p"/queue")
    body = html_response(conn, 200)

    assert String.contains?(body, "Operator Queue")
    assert String.contains?(body, "Render operator queue")
    assert String.contains?(body, "Open subject detail")
  end

  test "GET /reviews renders the pending review queue", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-701",
                 title: "Render pending review queue",
                 description: "Drive the reviews page through core",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-701"},
                 normalized_payload: %{"issue_id" => "ENG-701"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    conn = get(conn, ~p"/reviews")
    body = html_response(conn, 200)

    assert String.contains?(body, "Pending Reviews")
    assert String.contains?(body, "Render pending review queue")
    assert String.contains?(body, "Reject review")
    assert String.contains?(body, "Waive review")
  end

  test "GET /subjects/:subject_id renders the subject detail proving ground", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-710",
                 title: "Render subject detail",
                 description: "Drive the subject detail surface",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-710"},
                 normalized_payload: %{"issue_id" => "ENG-710"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    conn = get(conn, ~p"/subjects/#{result.payload.work_object_id}")
    body = html_response(conn, 200)

    assert String.contains?(body, "Render subject detail")
    assert String.contains?(body, "Operator controls")
    assert String.contains?(body, "Unified trace")
    assert String.contains?(body, "Issue read lease")
  end

  test "POST /subjects/:subject_id/actions/:action drives operator controls through the web shell",
       %{
         conn: conn,
         tenant_id: tenant_id,
         pack_version: pack_version
       } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-711",
                 title: "Pause from subject detail",
                 description: "Drive a real operator action",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-711"},
                 normalized_payload: %{"issue_id" => "ENG-711"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    conn =
      post(conn, ~p"/subjects/#{result.payload.work_object_id}/actions/pause", %{
        "reason" => "paused from controller test"
      })

    assert redirected_to(conn) == "/subjects/#{result.payload.work_object_id}"

    conn = get(recycle(conn), ~p"/subjects/#{result.payload.work_object_id}")
    body = html_response(conn, 200)

    assert String.contains?(body, "Resume")
  end

  test "POST /subjects/:subject_id/read-lease renders issued lease details", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-712",
                 title: "Issue read lease",
                 description: "Drive leased lower-read issuance",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-712"},
                 normalized_payload: %{"issue_id" => "ENG-712"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    installation_id =
      bootstrapped_installation_id!(tenant_id: tenant_id, pack_version: pack_version)

    ExecutionTraceFixture.seed_execution_trace!(
      tenant_id: tenant_id,
      installation_id: installation_id,
      subject_id: result.payload.work_object_id
    )

    conn = post(conn, ~p"/subjects/#{result.payload.work_object_id}/read-lease", %{})
    body = html_response(conn, 200)

    assert String.contains?(body, "Read lease issued")
    assert String.contains?(body, "Allowed ops")
  end

  test "POST /subjects/:subject_id/stream-attach-lease renders issued lease details", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-713",
                 title: "Issue stream attach lease",
                 description: "Drive leased stream issuance",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-713"},
                 normalized_payload: %{"issue_id" => "ENG-713"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    installation_id =
      bootstrapped_installation_id!(tenant_id: tenant_id, pack_version: pack_version)

    ExecutionTraceFixture.seed_execution_trace!(
      tenant_id: tenant_id,
      installation_id: installation_id,
      subject_id: result.payload.work_object_id
    )

    conn = post(conn, ~p"/subjects/#{result.payload.work_object_id}/stream-attach-lease", %{})
    body = html_response(conn, 200)

    assert String.contains?(body, "Stream attach lease issued")
    assert String.contains?(body, "Reconnect cursor")
  end

  test "GET /subjects/:subject_id keeps latest execution lineage visible after cancel", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-716",
                 title: "Cancelled lineage in the product shell",
                 description: "Expose terminal execution lineage through the real web surface",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-716"},
                 normalized_payload: %{"issue_id" => "ENG-716"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    installation_id =
      bootstrapped_installation_id!(tenant_id: tenant_id, pack_version: pack_version)

    barrier_id = Ecto.UUID.generate()

    ExecutionTraceFixture.seed_execution_trace!(
      tenant_id: tenant_id,
      installation_id: installation_id,
      subject_id: result.payload.work_object_id,
      execution_attrs: %{
        supersedes_execution_id: Ecto.UUID.generate(),
        barrier_id: barrier_id,
        last_reconcile_wave_id: "wave-1"
      },
      extra_audit_facts: [
        %{
          fact_kind: "execution_recovered",
          payload: %{
            "classification" => "reconciled",
            "last_reconcile_wave_id" => "wave-1"
          }
        },
        %{
          fact_kind: "execution_joined",
          payload: %{
            "join_step_ref" => "triage_join",
            "completed_children" => 2,
            "expected_children" => 2,
            "barrier_id" => barrier_id
          }
        }
      ]
    )

    assert {:ok, _read_lease} =
             ProductHost.issue_read_lease(result.payload.work_object_id,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    conn =
      post(conn, ~p"/subjects/#{result.payload.work_object_id}/actions/cancel", %{
        "reason" => "cancel from lineage controller test"
      })

    assert redirected_to(conn) == "/subjects/#{result.payload.work_object_id}"

    conn = get(recycle(conn), ~p"/subjects/#{result.payload.work_object_id}")
    body = html_response(conn, 200)

    assert String.contains?(body, "Live lineage posture")
    assert String.contains?(body, "Dispatch state")
    assert String.contains?(body, "cancelled")
    assert String.contains?(body, "Invalidated leases")
    assert String.contains?(body, "Reconcile wave")
    assert String.contains?(body, "Join step")
    assert String.contains?(body, "triage_join")
  end

  test "POST /reviews/:decision_id/decisions/:decision completes a pending review through the web shell",
       %{
         conn: conn,
         tenant_id: tenant_id,
         pack_version: pack_version
       } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-702",
                 title: "Accept pending review from the web shell",
                 description: "Drive the first review action",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-702"},
                 normalized_payload: %{"issue_id" => "ENG-702"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, reviews_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    pending_review = hd(reviews_page.page.entries)

    conn =
      post(conn, ~p"/reviews/#{pending_review.decision_ref.id}/decisions/accept", %{
        "decision_kind" => pending_review.decision_ref.decision_kind,
        "subject_id" => pending_review.subject_ref.id,
        "subject_kind" => to_string(pending_review.subject_ref.subject_kind),
        "reason" => "accepted from controller test"
      })

    assert redirected_to(conn) == "/reviews"

    assert {:ok, after_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    refute Enum.any?(
             after_page.page.entries,
             &(&1.decision_ref.id == pending_review.decision_ref.id)
           )
  end

  test "POST /reviews/:decision_id/decisions/:decision supports reject and waive through the web shell",
       %{
         conn: conn,
         tenant_id: tenant_id,
         pack_version: pack_version
       } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-714",
                 title: "Reject review from the web shell",
                 description: "Drive reject and waive review actions",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-714"},
                 normalized_payload: %{"issue_id" => "ENG-714"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, reviews_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    reject_review = hd(reviews_page.page.entries)

    conn =
      post(conn, ~p"/reviews/#{reject_review.decision_ref.id}/decisions/reject", %{
        "decision_kind" => reject_review.decision_ref.decision_kind,
        "subject_id" => reject_review.subject_ref.id,
        "subject_kind" => to_string(reject_review.subject_ref.subject_kind),
        "reason" => "rejected from controller test"
      })

    assert redirected_to(conn) == "/reviews"

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-715",
                 title: "Waive review from the web shell",
                 description: "Drive waive review action",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-715"},
                 normalized_payload: %{"issue_id" => "ENG-715"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, after_reject_page} =
             Queries.pending_reviews(%{}, tenant_id: tenant_id, pack_version: pack_version)

    waive_review = hd(after_reject_page.page.entries)

    conn =
      post(recycle(conn), ~p"/reviews/#{waive_review.decision_ref.id}/decisions/waive", %{
        "decision_kind" => waive_review.decision_ref.decision_kind,
        "subject_id" => waive_review.subject_ref.id,
        "subject_kind" => to_string(waive_review.subject_ref.subject_kind),
        "reason" => "waived from controller test"
      })

    assert redirected_to(conn) == "/reviews"
  end

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        activate_registration!(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        activate_registration!(registration)
    end
  end

  defp activate_registration!(%PackRegistration{} = registration) do
    deprecate_active_subject_kind_overlaps!(registration)
    assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
  end

  defp deprecate_active_subject_kind_overlaps!(%PackRegistration{} = registration) do
    subject_kinds = MapSet.new(registration.canonical_subject_kinds)
    assert {:ok, active_registrations} = PackRegistration.list_active()

    active_registrations
    |> Enum.reject(&(&1.id == registration.id))
    |> Enum.filter(fn active_registration ->
      active_subject_kinds = MapSet.new(active_registration.canonical_subject_kinds)
      not MapSet.disjoint?(subject_kinds, active_subject_kinds)
    end)
    |> Enum.each(fn active_registration ->
      assert {:ok, %PackRegistration{status: :deprecated}} =
               PackRegistration.deprecate(active_registration)
    end)
  end

  defp bootstrapped_installation_id!(opts) do
    assert {:ok, profile} = ProductBootstrap.ensure_bootstrapped(opts)
    profile.installation_ref.id
  end
end
