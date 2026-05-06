defmodule ExtravaganzaTest do
  use ExUnit.Case, async: true

  test "describes the proving-ground identity" do
    assert %{
             name: "Extravaganza",
             role: :proving_ground_product,
             posture: :operator_proving_ground
           } = Extravaganza.identity()
  end

  test "states an operator-surface mission" do
    assert String.contains?(Extravaganza.mission(), "operator product surface")
  end
end
