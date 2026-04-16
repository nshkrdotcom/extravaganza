defmodule Extravaganza.RuntimeProvisioner do
  @moduledoc """
  Bounded lower-runtime provisioner for current Mezzanine work planning.

  Until work planning is installation-native, Extravaganza still materializes
  the lower program/work-class profile from the product-owned config and pack
  data before driving the northbound AppKit bootstrap and intake surfaces.
  """

  alias Extravaganza.{
    Config,
    PlacementProfiles.LocalDefault,
    PolicyPresets,
    ProductInstallTemplate,
    ProductPack,
    WorkClasses.CodingOperations
  }

  alias Mezzanine.Surfaces.ProgramSurface

  @spec ensure_runtime_surface(Config.t()) ::
          {:ok,
           %{
             placement_profile: struct(),
             policy_bundle: struct(),
             program: struct(),
             work_class: struct()
           }}
          | {:error, term()}
  def ensure_runtime_surface(%Config{} = config) do
    tenant_id = config.tenant_id
    profile = runtime_profile(config)

    with {:ok, program} <- ensure_program(tenant_id, profile.program),
         {:ok, policy_bundle} <-
           ensure_policy_bundle(
             tenant_id,
             ProgramSurface.program_id(program),
             profile.policy_bundle
           ),
         {:ok, work_class} <-
           ensure_work_class(
             tenant_id,
             ProgramSurface.program_id(program),
             profile.work_class,
             ProgramSurface.policy_bundle_id(policy_bundle)
           ),
         {:ok, placement_profile} <-
           ensure_placement_profile(
             tenant_id,
             ProgramSurface.program_id(program),
             profile.placement_profile
           ) do
      {:ok,
       %{
         program: program,
         policy_bundle: policy_bundle,
         work_class: work_class,
         placement_profile: placement_profile
       }}
    end
  end

  defp runtime_profile(%Config{} = config) do
    %{
      program: %{
        slug: config.program_slug,
        name: config.program_name,
        product_family: config.product_family,
        configuration: %{
          "default_work_class" => config.work_class_name,
          "intake" => %{"source_kind" => config.linear_source_kind},
          "thin_host" => %{"operator_surface" => config.operator_surface_enabled?},
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

  defp ensure_program(tenant_id, attrs) do
    with {:ok, programs} <- ProgramSurface.list_programs(tenant_id) do
      case Enum.find(programs, &(ProgramSurface.program_slug(&1) == attrs.slug)) do
        nil -> create_and_activate_program(tenant_id, attrs)
        program -> update_existing_program(tenant_id, program, attrs)
      end
    end
  end

  defp create_and_activate_program(tenant_id, attrs) do
    with {:ok, program} <- ProgramSurface.create_program(tenant_id, attrs) do
      activate_program(tenant_id, program)
    end
  end

  defp activate_program(tenant_id, program) do
    if ProgramSurface.program_status(program) == :active do
      {:ok, program}
    else
      ProgramSurface.activate_program(tenant_id, ProgramSurface.program_id(program))
    end
  end

  defp update_existing_program(tenant_id, program, attrs) do
    with {:ok, updated_program} <-
           ProgramSurface.update_program(
             tenant_id,
             ProgramSurface.program_id(program),
             update_program_attrs(attrs)
           ) do
      activate_program(tenant_id, updated_program)
    end
  end

  defp ensure_policy_bundle(tenant_id, program_id, attrs) do
    with {:ok, bundles} <- ProgramSurface.list_policy_bundles(tenant_id, program_id) do
      case Enum.find(bundles, &(ProgramSurface.policy_bundle_name(&1) == attrs.name)) do
        nil ->
          ProgramSurface.load_policy_bundle(tenant_id, program_id, attrs)

        bundle ->
          ProgramSurface.recompile_policy_bundle(
            tenant_id,
            ProgramSurface.policy_bundle_id(bundle),
            update_policy_bundle_attrs(attrs)
          )
      end
    end
  end

  defp ensure_work_class(tenant_id, program_id, attrs, policy_bundle_id) do
    attrs = Map.put(attrs, :policy_bundle_id, policy_bundle_id)

    with {:ok, work_classes} <- ProgramSurface.list_work_classes(tenant_id, program_id) do
      case Enum.find(work_classes, &(ProgramSurface.work_class_name(&1) == attrs.name)) do
        nil ->
          ProgramSurface.create_work_class(tenant_id, program_id, attrs)

        work_class ->
          ProgramSurface.update_work_class(
            tenant_id,
            ProgramSurface.work_class_id(work_class),
            attrs
          )
      end
    end
  end

  defp ensure_placement_profile(tenant_id, program_id, attrs) do
    with {:ok, placement_profiles} <-
           ProgramSurface.list_placement_profiles(tenant_id, program_id) do
      case Enum.find(
             placement_profiles,
             &(ProgramSurface.placement_profile_profile_id(&1) == attrs.profile_id)
           ) do
        nil ->
          create_and_activate_placement_profile(tenant_id, program_id, attrs)

        placement_profile ->
          update_existing_placement_profile(tenant_id, placement_profile, attrs)
      end
    end
  end

  defp create_and_activate_placement_profile(tenant_id, program_id, attrs) do
    with {:ok, placement_profile} <-
           ProgramSurface.create_placement_profile(tenant_id, program_id, attrs) do
      activate_placement_profile(tenant_id, placement_profile)
    end
  end

  defp update_existing_placement_profile(tenant_id, placement_profile, attrs) do
    with {:ok, updated_profile} <-
           ProgramSurface.update_placement_profile(
             tenant_id,
             ProgramSurface.placement_profile_id(placement_profile),
             update_placement_profile_attrs(attrs)
           ) do
      activate_placement_profile(tenant_id, updated_profile)
    end
  end

  defp activate_placement_profile(tenant_id, placement_profile) do
    if ProgramSurface.placement_profile_status(placement_profile) == :active do
      {:ok, placement_profile}
    else
      ProgramSurface.activate_placement_profile(
        tenant_id,
        ProgramSurface.placement_profile_id(placement_profile)
      )
    end
  end

  defp update_program_attrs(attrs) do
    Map.take(attrs, [:name, :product_family, :configuration, :metadata])
  end

  defp update_policy_bundle_attrs(attrs) do
    Map.take(attrs, [:version, :source_ref, :body, :metadata])
  end

  defp update_placement_profile_attrs(attrs) do
    Map.take(attrs, [
      :strategy,
      :target_selector,
      :runtime_preferences,
      :workspace_policy,
      :metadata
    ])
  end
end
