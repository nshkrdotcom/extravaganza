defmodule ExtravaganzaTest do
  use ExUnit.Case, async: true

  test "describes the proving-ground identity" do
    assert %{
             name: "Extravaganza",
             role: :proving_ground_product,
             posture: :thin_surface
           } = Extravaganza.identity()
  end

  test "states a thin-surface mission" do
    assert Extravaganza.mission() =~ "operator surface"
  end
end
