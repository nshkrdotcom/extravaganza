defmodule Extravaganza.ProgramRegistry do
  @moduledoc """
  Product-owned registry for the default Extravaganza program profile.
  """

  alias Extravaganza.Config
  alias Extravaganza.PlacementProfiles.LocalDefault
  alias Extravaganza.PolicyPresets
  alias Extravaganza.WorkClasses.CodingOperations

  @spec default_profile(keyword() | map()) :: map()
  def default_profile(overrides \\ []) do
    config = Config.load(overrides)

    %{
      config: config,
      program: %{
        slug: config.program_slug,
        name: config.program_name,
        product_family: config.product_family,
        configuration: %{
          "default_work_class" => config.work_class_name,
          "intake" => %{"source_kind" => config.linear_source_kind},
          "thin_host" => %{"operator_surface" => config.operator_surface_enabled?}
        },
        metadata: %{"product" => "extravaganza", "profile" => "default"}
      },
      policy_bundle:
        PolicyPresets.default_coding_ops()
        |> Map.put(:name, config.policy_bundle_name)
        |> Map.put(:version, config.policy_bundle_version),
      work_class:
        CodingOperations.definition()
        |> Map.put(:name, config.work_class_name)
        |> Map.put(:kind, config.work_class_kind),
      placement_profile:
        LocalDefault.profile()
        |> Map.put(:profile_id, config.placement_profile_id)
    }
  end
end
