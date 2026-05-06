defmodule ExtravaganzaAtomCleanupTest do
  use ExUnit.Case, async: true

  alias Extravaganza.{Config, ProductInstallTemplate, ProductPack}

  @repo_root Path.expand("../../..", __DIR__)

  @owner_files [
    "apps/extravaganza_core/lib/extravaganza/config.ex",
    "apps/extravaganza_core/lib/extravaganza/default_authoring_bundle.ex",
    "apps/extravaganza_core/lib/extravaganza/product_install_template.ex",
    "apps/extravaganza_core/lib/extravaganza/product_pack.ex",
    "apps/extravaganza_core/lib/extravaganza/product_profile.ex",
    "apps/extravaganza_core/lib/extravaganza/policy_presets.ex",
    "apps/extravaganza_core/lib/extravaganza/policy_presets/default_coding_ops.ex",
    "apps/extravaganza_core/lib/extravaganza/placement_profiles/local_default.ex"
  ]

  @forbidden_atom_constructors [
    "String" <> ".to_atom",
    "String" <> ".to_existing_atom",
    "binary" <> "_to_atom",
    "binary" <> "_to_existing_atom",
    "list" <> "_to_atom",
    "list" <> "_to_existing_atom",
    ":" <> "\"" <> "#" <> "{"
  ]

  test "product atom owner files do not call dynamic atom constructors" do
    for file <- @owner_files do
      contents = File.read!(Path.join(@repo_root, file))

      for constructor <- @forbidden_atom_constructors do
        refute String.contains?(contents, constructor),
               "#{file} contains forbidden atom constructor #{constructor}"
      end
    end
  end

  test "unknown ProductPack names reject before product refs are built" do
    assert_product_pack_rejects(work_class_kind: unique_product_pack_name("subject"))
    assert_product_pack_rejects(linear_source_kind: unique_product_pack_name("source"))
    assert_product_pack_rejects(work_class_name: unique_product_pack_name("recipe"))
    assert_product_pack_rejects(placement_profile_id: unique_product_pack_name("placement"))
  end

  test "derived source binding and placement names stay bounded" do
    assert_product_install_template_rejects(
      [linear_source_kind: unique_product_pack_name("source-binding")],
      :source_binding_ref
    )

    assert_product_install_template_rejects(
      [placement_profile_id: unique_product_pack_name("placement-binding")],
      :placement_profile_id
    )
  end

  defp assert_product_pack_rejects(overrides) do
    ProductPack.manifest(overrides)
    flunk("ProductPack accepted invalid config #{inspect(overrides)}")
  rescue
    ArgumentError -> :ok
  end

  defp assert_product_install_template_rejects(overrides, field) do
    overrides
    |> Config.load()
    |> ProductInstallTemplate.default()

    flunk("Product install template accepted invalid config #{inspect(overrides)}")
  rescue
    error in [ArgumentError] ->
      assert String.contains?(Exception.message(error), "unknown ProductPack #{field}")
  end

  defp unique_product_pack_name(prefix),
    do: prefix <> "_" <> Integer.to_string(System.unique_integer([:positive]))
end
