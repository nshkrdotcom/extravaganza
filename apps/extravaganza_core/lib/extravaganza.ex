defmodule Extravaganza do
  @moduledoc """
  Thin proving-ground product surface above AppKit and Mezzanine.
  """

  @doc """
  Returns a compact identity map for the proving-ground product.
  """
  @spec identity() :: map()
  def identity do
    %{
      name: "Extravaganza",
      role: :proving_ground_product,
      posture: :thin_surface,
      downstream: [:app_kit, :mezzanine]
    }
  end

  @doc """
  States the intended product mission for the first proving deployment.
  """
  @spec mission() :: String.t()
  def mission do
    "Prove a sophisticated operator surface while keeping reusable business machinery below the product boundary."
  end
end
