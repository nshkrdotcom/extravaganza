defmodule Extravaganza.Workflows do
  @moduledoc """
  Product-local workflow commands over AppKit.
  """

  alias AppKit.Core.RunRequest
  alias AppKit.{WorkControl, WorkSurface}

  alias Extravaganza.{
    CodingOpsTemplates,
    Config,
    PolicyPresets,
    ProductPack,
    ProductSurface,
    RunProfiles.DefaultCodexProfile,
    SymphonyWorkflowImport
  }

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, policy_config} <- start_runtime_policy_config(opts),
         :ok <- validate_runtime_profile_compatibility(config, policy_config),
         {:ok, subject_ref} <- WorkSurface.ingest_subject(context, Map.new(domain_call)),
         idempotency_key = idempotency_key(context, subject_ref, config),
         context = %{context | idempotency_key: idempotency_key},
         {:ok, run_request} <-
           RunRequest.new(
             run_request_attrs(subject_ref, config, context, idempotency_key, policy_config)
           ) do
      WorkControl.start_run(context, run_request, ProductSurface.work_control_opts(config, opts))
    end
  end

  @doc false
  @spec validate_runtime_profile_compatibility(Config.t(), map()) :: :ok | {:error, term()}
  def validate_runtime_profile_compatibility(
        %Config{} = config,
        policy_config \\ PolicyPresets.DefaultCodingOps.runtime_config()
      )
      when is_map(policy_config) do
    selection = DefaultCodexProfile.selection()
    slots = ProductPack.profile_slots(config)
    run_config = Map.get(policy_config, "run", %{})
    granted_capability_ids = capability_ids(policy_config)

    cond do
      Atom.to_string(slots.runtime_profile_ref) != selection["runtime_profile_ref"] ->
        incompatible(:runtime_profile_ref, Atom.to_string(slots.runtime_profile_ref), selection)

      Map.get(run_config, "profile") != selection["runtime_profile_key"] ->
        incompatible(:runtime_profile_key, Map.get(run_config, "profile"), selection)

      Map.get(run_config, "runtime_class") != selection["runtime_class"] ->
        incompatible(:runtime_class, Map.get(run_config, "runtime_class"), selection)

      Map.get(run_config, "lower_runtime_kind") != selection["lower_runtime_kind"] ->
        incompatible(:lower_runtime_kind, Map.get(run_config, "lower_runtime_kind"), selection)

      Map.get(run_config, "capability") != selection["capability_id"] ->
        incompatible(:capability_id, Map.get(run_config, "capability"), selection)

      Map.get(run_config, "target") != selection["target_ref"] ->
        incompatible(:target_ref, Map.get(run_config, "target"), selection)

      selection["capability_id"] not in granted_capability_ids ->
        incompatible(:capability_grant, granted_capability_ids, selection)

      true ->
        :ok
    end
  end

  defp run_request_attrs(subject_ref, config, context, idempotency_key, policy_config) do
    %{
      subject_ref: subject_ref,
      recipe_ref: ProductPack.execution_recipe_ref(config),
      params: %{"runtime_policy_config" => policy_config},
      metadata:
        run_metadata(config, policy_config, pack_revision(context))
        |> Map.put("idempotency_key", idempotency_key)
    }
  end

  defp run_metadata(config, policy_config, pack_revision) do
    slots = ProductPack.profile_slots(config)
    recipe_ref = ProductPack.execution_recipe_ref(config)
    source_binding_ref = ProductPack.source_binding_key(config)
    selection = DefaultCodexProfile.selection()

    %{
      "product_family" => config.product_family,
      "pack_slug" => ProductPack.pack_slug(config),
      "pack_version" => ProductPack.pack_version(config),
      "pack_revision" => pack_revision,
      "recipe_ref" => recipe_ref,
      "runtime_profile_ref" => selection["runtime_profile_ref"],
      "runtime_profile_kind" => selection["runtime_profile_kind"],
      "runtime_profile_revision" => selection["runtime_profile_revision"],
      "lower_runtime_kind" => selection["lower_runtime_kind"],
      "requested_action_ids" => [selection["capability_id"]],
      "requested_capability_ids" => capability_ids(policy_config),
      "source_binding_refs" => [source_binding_ref],
      "resource_scope_refs" => [
        "source_binding://#{source_binding_ref}",
        "workspace-policy://#{config.program_slug}/#{config.work_class_name}"
      ],
      "source_binding_ref" => source_binding_ref,
      "workspace_policy_ref" =>
        "workspace-policy://#{config.program_slug}/#{config.work_class_name}",
      "runtime_params_ref" => "runtime-params://#{config.program_slug}/#{recipe_ref}/default",
      "live_provider_allowed" => false,
      "evidence_profile_ref" => Atom.to_string(slots.evidence_profile_ref),
      "memory_profile_ref" => Atom.to_string(slots.memory_profile_ref),
      "context_profile_ref" => memory_config(policy_config)["context_profile_ref"],
      "memory_context_required" => memory_config(policy_config)["required_for_run"],
      "memory_context_source_refs" => ["workspace_memory"],
      "memory_context_binding_keys" => ["shared_memory"],
      "redaction_profile_ref" => "redaction://extravaganza/default",
      "prompt_context_recipe_refs" => [CodingOpsTemplates.prompt_ref()]
    }
    |> put_future_work_policy_metadata(policy_config)
  end

  defp start_runtime_policy_config(opts) do
    if profile_cache_path_requested?(opts) do
      SymphonyWorkflowImport.runtime_policy_config_from_cache(opts)
    else
      {:ok, PolicyPresets.DefaultCodingOps.runtime_config()}
    end
  end

  defp profile_cache_path_requested?(opts) do
    Keyword.has_key?(opts, :profile_cache_path) or Keyword.has_key?(opts, :cache_path)
  end

  defp put_future_work_policy_metadata(metadata, %{"future_work_policy" => policy})
       when is_map(policy) do
    scope = Map.get(policy, "scope") || %{}

    metadata
    |> Map.put("future_work_policy_ref", Map.get(policy, "policy_ref"))
    |> Map.put("future_work_policy_scope", Map.get(scope, "applies_to"))
    |> Map.put("mutates_active_runs?", Map.get(scope, "mutates_active_runs?"))
  end

  defp put_future_work_policy_metadata(metadata, _policy_config), do: metadata

  defp memory_config(policy_config), do: Map.get(policy_config, "memory", %{})

  defp capability_ids(policy_config) do
    policy_config
    |> Map.get("capability_grants", [])
    |> Enum.flat_map(fn
      %{"capability_id" => capability_id} when is_binary(capability_id) -> [capability_id]
      %{capability_id: capability_id} when is_binary(capability_id) -> [capability_id]
      _other -> []
    end)
  end

  defp incompatible(field, actual, selection) do
    {:error,
     {:incompatible_product_runtime_profile,
      %{
        field: field,
        actual: actual,
        expected_selection: selection
      }}}
  end

  defp idempotency_key(context, subject_ref, config) do
    "extravaganza:start_run:#{config.program_slug}:#{pack_revision(context)}:#{subject_ref.id}:#{ProductPack.execution_recipe_ref(config)}"
  end

  defp pack_revision(context) do
    case context.installation_ref do
      %{compiled_pack_revision: revision} when not is_nil(revision) -> revision
      _other -> 1
    end
  end
end
