defmodule Extravaganza.ProductProfile do
  @moduledoc """
  Product-owned install and runtime profile payload for governed bootstrap.
  """

  alias Extravaganza.{
    Config,
    PlacementProfiles.LocalDefault,
    PolicyPresets,
    ProductInstallTemplate,
    ProductPack,
    RunProfiles.DefaultCodexProfile,
    WorkClasses.CodingOperations
  }

  @spec profile(Config.t()) :: map()
  def profile(%Config{} = config) do
    %{
      program: %{
        slug: config.program_slug,
        name: config.program_name,
        product_family: config.product_family,
        configuration: %{
          "default_work_class" => config.work_class_name,
          "intake" => %{"source_kind" => config.linear_source_kind},
          "product_surface" => %{"operator_surface" => config.operator_surface_enabled?},
          "runtime_profile" => DefaultCodexProfile.selection(),
          "app_kit" => %{
            "pack_slug" => ProductPack.pack_slug(config),
            "pack_version" => ProductPack.pack_version(config),
            "install_template_key" => ProductInstallTemplate.template_key(config)
          }
        },
        metadata: %{
          "product" => "extravaganza",
          "profile" => "default",
          "pack_slug" => ProductPack.pack_slug(config),
          "pack_version" => ProductPack.pack_version(config)
        }
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
