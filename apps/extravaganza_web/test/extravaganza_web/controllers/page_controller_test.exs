defmodule ExtravaganzaWeb.PageControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.{ProductPack, Queries, Workflows}
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Pack.Compiler

  test "GET / renders the product shell", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Extravaganza"
    assert html_response(conn, 200) =~ "proving-ground product"
  end

  test "GET /queue renders the first core-backed operator queue", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, _run} =
             Workflows.start_run(
               %{
                 external_ref: "linear:ENG-601",
                 title: "Render first operator queue",
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

    assert body =~ "Operator Queue"
    assert body =~ "Render first operator queue"
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

    assert body =~ "Pending Reviews"
    assert body =~ "Render pending review queue"
  end

  test "POST /reviews/:decision_id/accept completes a pending review through the web shell", %{
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
      post(conn, ~p"/reviews/#{pending_review.decision_ref.id}/accept", %{
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

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
    end
  end
end
