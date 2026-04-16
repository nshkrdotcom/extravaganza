defmodule ExtravaganzaWeb.PageControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.{ProductPack, Workflows}
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
