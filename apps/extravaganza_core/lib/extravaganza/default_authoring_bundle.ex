defmodule Extravaganza.DefaultAuthoringBundle do
  @moduledoc """
  Builds the default Extravaganza authoring-bundle import envelope.

  ProductPack is the product-owned seed; the checksum/schema-validated
  authoring bundle imported through AppKit is the runtime policy authority.
  """

  alias AppKit.Core.{AuthoringBundleImport, InstallationRef}

  alias Extravaganza.{
    Config,
    ProductInstallTemplate,
    ProductPack
  }

  alias Mezzanine.Pack.{ExecutionRecipeSpec, Manifest, Serializer}

  @policy_refs ["extravaganza.coding_ops.v1"]
  @runtime_frontmatter_sections [
    "run",
    "approval",
    "retry",
    "placement",
    "workspace",
    "capability_grants"
  ]
  @policy_compare_fields [:retry, :placement, :sandbox, :tools, :hooks]

  @spec build(Config.t(), InstallationRef.t() | keyword()) ::
          {:ok, AuthoringBundleImport.t()} | {:error, term()}
  def build(config, opts \\ [])

  def build(%Config{} = config, %InstallationRef{} = installation_ref) do
    build(config, installation_ref: installation_ref)
  end

  def build(%Config{} = config, opts) when is_list(opts) do
    manifest = ProductPack.manifest(config)
    product_policy = runtime_policy(manifest)
    workflow_policy = workflow_runtime_policy(Keyword.get(opts, :workflow_body))
    bundle_policy = Keyword.get(opts, :bundle_runtime_policy, product_policy)

    with :ok <- reject_workflow_policy(product_policy, workflow_policy),
         :ok <- reject_bundle_conflict(product_policy, bundle_policy) do
      manifest_payload = Serializer.serialize_manifest(manifest)
      attrs = unsigned_attrs(config, manifest_payload, opts)
      attrs = Map.put(attrs, "checksum", AuthoringBundleImport.checksum_for(attrs))
      AuthoringBundleImport.new(attrs)
    end
  end

  @spec runtime_policy(Manifest.t()) :: map()
  def runtime_policy(%Manifest{execution_recipe_specs: [recipe | _rest]}) do
    recipe_policy(recipe)
  end

  def runtime_policy(%Manifest{}), do: %{}

  @spec default_installation_id() :: String.t()
  def default_installation_id, do: "default"

  defp unsigned_attrs(%Config{} = config, manifest_payload, opts) do
    attrs = %{
      "bundle_id" => bundle_id(config),
      "tenant_id" => config.tenant_id,
      "installation_id" => installation_id(opts),
      "pack_manifest" => manifest_payload,
      "lifecycle_specs" => manifest_payload["lifecycle_specs"],
      "decision_specs" => manifest_payload["decision_specs"],
      "binding_descriptors" => ProductInstallTemplate.default(config).default_bindings,
      "observer_descriptors" => [],
      "context_adapter_descriptors" => [],
      "policy_refs" => @policy_refs,
      "authored_by" => "operator:extravaganza",
      "metadata" => %{
        "policy_authority" => "authoring_bundle_installation_revision",
        "product_pack_role" => "seed",
        "workflow_body_role" => "prompt_template"
      }
    }

    case expected_installation_revision(opts) do
      nil -> attrs
      revision -> Map.put(attrs, "expected_installation_revision", revision)
    end
  end

  defp bundle_id(%Config{} = config), do: "#{config.program_slug}-default-#{config.pack_version}"

  defp installation_id(opts) do
    case Keyword.get(opts, :installation_ref) do
      %InstallationRef{id: id} when is_binary(id) and id != "" ->
        id

      _other ->
        Keyword.get(opts, :installation_id, default_installation_id())
    end
  end

  defp expected_installation_revision(opts) do
    case Keyword.fetch(opts, :expected_installation_revision) do
      {:ok, revision} ->
        revision

      :error ->
        case Keyword.get(opts, :installation_ref) do
          %InstallationRef{compiled_pack_revision: revision} -> revision
          _other -> nil
        end
    end
  end

  defp recipe_policy(%ExecutionRecipeSpec{} = recipe) do
    %{
      retry: retry_policy(recipe.retry_config),
      placement: %{placement_ref: recipe.placement_ref},
      sandbox: %{sandbox_policy_ref: recipe.sandbox_policy_ref},
      tools: %{dynamic_tool_manifest: recipe.dynamic_tool_manifest},
      hooks: %{hook_stages: recipe.hook_stages}
    }
  end

  defp retry_policy(retry_config) when is_map(retry_config) do
    %{
      max_attempts: Map.get(retry_config, :max_attempts),
      backoff: Map.get(retry_config, :backoff)
    }
  end

  defp reject_workflow_policy(_product_policy, policy) when policy == %{}, do: :ok

  defp reject_workflow_policy(product_policy, workflow_policy) do
    field = conflict_field(product_policy, workflow_policy)

    {:error,
     {:runtime_policy_conflict,
      %{
        field: field,
        source: :workflow_body,
        final_owner: :authoring_bundle,
        product_pack: product_policy,
        workflow_body: workflow_policy
      }}}
  end

  defp reject_bundle_conflict(product_policy, bundle_policy) do
    case conflict_field(product_policy, bundle_policy) do
      nil ->
        :ok

      field ->
        {:error,
         {:runtime_policy_conflict,
          %{
            field: field,
            source: :authoring_bundle,
            final_owner: :authoring_bundle,
            product_pack: product_policy,
            authoring_bundle: bundle_policy
          }}}
    end
  end

  defp conflict_field(product_policy, compared_policy) when is_map(compared_policy) do
    Enum.find(@policy_compare_fields, fn field ->
      compared = Map.get(compared_policy, field)
      not is_nil(compared) and compared != Map.get(product_policy, field)
    end)
  end

  defp conflict_field(_product_policy, _compared_policy), do: :runtime_policy

  defp workflow_runtime_policy(nil), do: %{}

  defp workflow_runtime_policy(body) when is_binary(body), do: workflow_policy(body)

  defp workflow_policy(body) do
    body
    |> frontmatter_lines()
    |> frontmatter_policy()
  end

  defp frontmatter_lines(body) do
    body
    |> String.split("\n", trim: false)
    |> Enum.drop_while(&(String.trim(&1) == ""))
    |> case do
      [first | rest] ->
        if String.trim(first) == "---" do
          Enum.take_while(rest, &(String.trim(&1) != "---"))
        else
          []
        end

      _other ->
        []
    end
  end

  defp frontmatter_policy([]), do: %{}

  defp frontmatter_policy(lines) do
    {sections, retry} =
      Enum.reduce(lines, {MapSet.new(), %{}}, fn line, {sections, retry} ->
        trimmed = String.trim(line)
        section = runtime_section(trimmed)

        cond do
          section ->
            {MapSet.put(sections, section), retry}

          MapSet.member?(sections, "retry") ->
            {sections, retry_line(trimmed, retry)}

          true ->
            {sections, retry}
        end
      end)

    retry =
      case retry do
        retry when map_size(retry) > 0 -> %{retry: retry}
        _other -> %{}
      end

    if MapSet.size(sections) == 0 do
      %{}
    else
      Map.put_new(retry, :runtime_sections, Enum.sort(MapSet.to_list(sections)))
    end
  end

  defp runtime_section(trimmed) do
    Enum.find(@runtime_frontmatter_sections, fn section ->
      trimmed == "#{section}:"
    end)
  end

  defp retry_line("max_attempts: " <> attempts, retry) do
    case Integer.parse(String.trim(attempts)) do
      {attempts, ""} -> Map.put(retry, :max_attempts, attempts)
      _other -> retry
    end
  end

  defp retry_line("strategy: " <> strategy, retry) do
    case String.trim(strategy) do
      "linear" -> Map.put(retry, :backoff, :linear)
      "exponential" -> Map.put(retry, :backoff, :exponential)
      _other -> retry
    end
  end

  defp retry_line(_line, retry), do: retry
end
