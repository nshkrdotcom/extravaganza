defmodule Extravaganza.Config do
  @moduledoc """
  Normalized product-core configuration for the Extravaganza proving product.
  """

  @enforce_keys [
    :tenant_id,
    :program_slug,
    :program_name,
    :product_family,
    :pack_version,
    :policy_bundle_name,
    :policy_bundle_version,
    :work_class_name,
    :work_class_kind,
    :placement_profile_id,
    :execution_timeout_ms,
    :linear_source_kind,
    :operator_surface_enabled?
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          program_slug: String.t(),
          program_name: String.t(),
          product_family: String.t(),
          pack_version: String.t(),
          policy_bundle_name: String.t(),
          policy_bundle_version: String.t(),
          work_class_name: String.t(),
          work_class_kind: String.t(),
          placement_profile_id: String.t(),
          execution_timeout_ms: pos_integer(),
          linear_source_kind: String.t(),
          operator_surface_enabled?: boolean()
        }

  @spec load(keyword() | map()) :: t()
  def load(overrides \\ []) do
    configured =
      :extravaganza_core
      |> Application.get_env(__MODULE__, [])
      |> Enum.into(%{})
      |> Map.merge(Map.new(overrides))

    %__MODULE__{
      tenant_id: Map.fetch!(configured, :tenant_id),
      program_slug: Map.fetch!(configured, :program_slug),
      program_name: Map.fetch!(configured, :program_name),
      product_family: Map.fetch!(configured, :product_family),
      pack_version: Map.fetch!(configured, :pack_version),
      policy_bundle_name: Map.fetch!(configured, :policy_bundle_name),
      policy_bundle_version: Map.fetch!(configured, :policy_bundle_version),
      work_class_name: Map.fetch!(configured, :work_class_name),
      work_class_kind: Map.fetch!(configured, :work_class_kind),
      placement_profile_id: Map.fetch!(configured, :placement_profile_id),
      execution_timeout_ms: Map.fetch!(configured, :execution_timeout_ms),
      linear_source_kind: Map.fetch!(configured, :linear_source_kind),
      operator_surface_enabled?: Map.fetch!(configured, :operator_surface_enabled?)
    }
  end
end
