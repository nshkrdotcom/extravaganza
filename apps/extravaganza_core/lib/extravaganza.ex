defmodule Extravaganza do
  @moduledoc """
  Operator proving-ground product surface above AppKit.

  Product-owned pack definitions remain part of the product, but they compile
  against the pure pack-model contract instead of expanding the operational
  runtime path below AppKit.
  """

  @doc """
  Returns a compact identity map for the proving-ground product.
  """
  @spec identity() :: map()
  def identity do
    %{
      name: "Extravaganza",
      role: :proving_ground_product,
      posture: :operator_proving_ground,
      downstream: [:app_kit],
      pack_contract: :mezzanine_pack_model
    }
  end

  @doc """
  States the intended product mission for the first proving deployment.
  """
  @spec mission() :: String.t()
  def mission do
    "Prove a real operator product surface while keeping reusable business machinery below the product boundary."
  end
end
