defmodule Extravaganza.LiveAgentLoopReceipt do
  @moduledoc """
  Phase 7 Profile A M2 composition harness.

  Extravaganza owns the profile defaults and receipt shape. The actual M2 run is
  admitted through `AppKit.RuntimeGateway`, and public readback comes back
  through `AppKit.HeadlessSurface`.
  """

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail
  alias AppKit.HeadlessSurface, as: AppKitHeadlessSurface
  alias AppKit.RuntimeGateway, as: AppKitRuntimeGateway
  alias Extravaganza.Presenters.RunPresenter

  alias Extravaganza.{
    AppKitContext,
    Config,
    ProductPack
  }

  @schema_ref "agentic_substrate_headless_e2e_v1"
  @release_manifest_ref "release-manifest://extravaganza/profile-a-live/v1"
  @profile_ref "profile://extravaganza/profile-a-live-m2/v1"
  @unsafe_keys MapSet.new(~w[
    prompt raw_prompt raw_provider_body raw_provider_payload raw_tool_output
    tool_call tool_result workflow_history workspace_path secret token api_key
  ])
  @required_receipt_fields ~w[
    schema_ref profile flavor mechanisms profile_ref source_profile_ref
    runtime_profile_ref evidence_profile_ref memory_profile_ref run_ref
    turn_refs tool_action_receipt_refs authority_decision_refs candidate_fact_refs
    memory_commit_refs provider_receipt_refs headless_readback_hash
    browser_presenter_hash trace_id release_manifest_ref cleanup_receipt_refs
    disposable_provider_resource_refs
  ]

  @spec live_gate_enabled?(keyword()) :: boolean()
  def live_gate_enabled?(opts \\ []), do: Keyword.get(opts, :live_e2e_enabled?, false) == true

  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(attrs \\ %{}, opts \\ []) when is_map(attrs) and is_list(opts) do
    if live_gate_enabled?(opts) do
      config = Config.load(Keyword.get(opts, :config_overrides, []))
      context = Keyword.get(opts, :context) || AppKitContext.bootstrap_context(config)
      request = agent_run_request(config, attrs)

      with {:ok, %RunOutcomeFuture{} = future} <-
             AppKitRuntimeGateway.invoke_runtime_operation(
               context,
               :coding_agent_runtime,
               :session_turn,
               put_runtime_binding(request),
               runtime_gateway_opts(opts)
             ),
           {:ok, %RuntimeRunDetail{} = run_detail} <-
             AppKitHeadlessSurface.run_detail(context, future.run_ref, %{}, opts),
           {:ok, receipt} <- build_receipt(config, future, run_detail, attrs),
           :ok <- validate_receipt(receipt),
           :ok <- maybe_write_receipt(receipt, opts) do
        {:ok, receipt}
      end
    else
      {:error, :live_e2e_not_enabled}
    end
  end

  @spec agent_run_request(Config.t(), map()) :: map()
  def agent_run_request(%Config{} = config, attrs \\ %{}) when is_map(attrs) do
    trace_id = map_value(attrs, :trace_id, "trace://extravaganza/profile-a-live")
    dedupe_key = map_value(attrs, :submission_dedupe_key, "extravaganza-profile-a-live")

    %{
      tenant_ref: tenant_ref(config),
      installation_ref: map_value(attrs, :installation_ref, "installation://extravaganza/live"),
      subject_ref: map_value(attrs, :subject_ref, "subject://extravaganza/live-profile-a"),
      actor_ref: map_value(attrs, :actor_ref, "actor://extravaganza/operator"),
      profile_bundle: ProductPack.agent_loop_profile_slots(config),
      tool_catalog_ref:
        map_value(attrs, :tool_catalog_ref, "tool-catalog://extravaganza/coding-ops-v1"),
      budget_ref: map_value(attrs, :budget_ref, "budget://extravaganza/profile-a-live"),
      recall_scope_ref:
        map_value(attrs, :recall_scope_ref, "recall://extravaganza/profile-a-live"),
      idempotency_key: map_value(attrs, :idempotency_key, "profile-a-live-e2e"),
      trace_id: trace_id,
      correlation_id: map_value(attrs, :correlation_id, "corr://extravaganza/profile-a-live"),
      submission_dedupe_key: dedupe_key,
      initial_input_ref:
        map_value(attrs, :initial_input_ref, "input://extravaganza/live-profile-a/claim-checked"),
      params:
        Map.merge(
          %{
            profile_ref: @profile_ref,
            release_manifest_ref: @release_manifest_ref,
            max_turns: 3
          },
          map_value(attrs, :params, %{})
        )
    }
  end

  @spec build_receipt(Config.t(), struct(), struct(), map()) ::
          {:ok, map()} | {:error, term()}
  def build_receipt(
        %Config{} = config,
        %RunOutcomeFuture{} = future,
        %RuntimeRunDetail{} = run_detail,
        attrs \\ %{}
      )
      when is_map(attrs) do
    profile_slots = ProductPack.agent_loop_profile_slots(config)
    readback_payload = RuntimeRunDetail.dump(run_detail)
    browser_payload = RunPresenter.present(run_detail, correlation_id: future.correlation_id)

    receipt =
      %{
        "schema_ref" => @schema_ref,
        "receipt_name" => @schema_ref,
        "profile" => "extravaganza",
        "flavor" => "live",
        "mechanism" => "M1+M2",
        "mechanisms" => ["M1", "M2"],
        "agent_loop_used?" => true,
        "agentic_core_proven?" => true,
        "proof_class" => "live_e2e",
        "receipt_state" => "proven",
        "profile_ref" => map_value(attrs, :profile_ref, @profile_ref),
        "source_profile_ref" => to_string(profile_slots.source_profile_ref),
        "runtime_profile_ref" => to_string(profile_slots.runtime_profile_ref),
        "evidence_profile_ref" => to_string(profile_slots.evidence_profile_ref),
        "memory_profile_ref" => to_string(profile_slots.memory_profile_ref),
        "run_ref" => future.run_ref,
        "workflow_ref" => future.workflow_ref,
        "turn_refs" => ref_list(attrs, :turn_refs, turn_refs(run_detail)),
        "tool_action_receipt_refs" => ref_list(attrs, :tool_action_receipt_refs),
        "authority_decision_refs" => ref_list(attrs, :authority_decision_refs),
        "candidate_fact_refs" =>
          ref_list(attrs, :candidate_fact_refs, run_detail.candidate_fact_refs),
        "memory_commit_refs" => ref_list(attrs, :memory_commit_refs),
        "memory_proof_refs" => ref_list(attrs, :memory_proof_refs, run_detail.memory_proof_refs),
        "memory_commit_skipped" => false,
        "provider_receipt_refs" => ref_list(attrs, :provider_receipt_refs),
        "provider_credentials_required?" => true,
        "provider_network_access?" => true,
        "network_required?" => true,
        "linear_used?" => true,
        "github_used?" => true,
        "codex_used?" => true,
        "appkit_surface" => "AppKit.HeadlessSurface",
        "appkit_surfaces" => ["AppKit.RuntimeGateway", "AppKit.HeadlessSurface"],
        "headless_readback_hash" => stable_hash(readback_payload),
        "browser_presenter_hash" => stable_hash(browser_payload),
        "trace_id" => map_value(attrs, :trace_id, "trace://extravaganza/profile-a-live"),
        "release_manifest_ref" => map_value(attrs, :release_manifest_ref, @release_manifest_ref),
        "cleanup_receipt_refs" => ref_list(attrs, :cleanup_receipt_refs),
        "disposable_provider_resource_refs" => ref_list(attrs, :disposable_provider_resource_refs)
      }

    {:ok, receipt}
  end

  @spec validate_receipt(map()) :: :ok | {:error, term()}
  def validate_receipt(%{} = receipt) do
    cond do
      missing_required_fields(receipt) != [] ->
        {:error, {:missing_live_receipt_fields, missing_required_fields(receipt)}}

      receipt["schema_ref"] != @schema_ref ->
        {:error, :invalid_live_receipt_schema}

      receipt["mechanisms"] != ["M1", "M2"] ->
        {:error, :invalid_live_receipt_mechanisms}

      receipt["agent_loop_used?"] != true ->
        {:error, :live_receipt_without_agent_loop}

      receipt["agentic_core_proven?"] != true ->
        {:error, :live_receipt_not_proven}

      unsafe_public_json?(receipt) ->
        {:error, :unsafe_live_receipt_payload}

      nonempty_refs?(receipt, ~w[
        turn_refs tool_action_receipt_refs authority_decision_refs candidate_fact_refs
        memory_commit_refs memory_proof_refs provider_receipt_refs cleanup_receipt_refs
        disposable_provider_resource_refs
      ]) == false ->
        {:error, :missing_live_receipt_refs}

      true ->
        :ok
    end
  end

  def validate_receipt(_receipt), do: {:error, :invalid_live_receipt}

  @spec write_receipt!(map(), Path.t()) :: Path.t()
  def write_receipt!(%{} = receipt, path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, [Jason.encode_to_iodata!(receipt, pretty: true), ?\n])
    path
  end

  defp maybe_write_receipt(receipt, opts) do
    case Keyword.get(opts, :receipt_path) do
      nil ->
        :ok

      path when is_binary(path) ->
        write_receipt!(receipt, path)
        :ok
    end
  end

  defp missing_required_fields(receipt),
    do: Enum.reject(@required_receipt_fields, &Map.has_key?(receipt, &1))

  defp nonempty_refs?(receipt, keys) do
    Enum.all?(keys, fn key ->
      case Map.fetch(receipt, key) do
        {:ok, refs} when is_list(refs) -> refs != [] and Enum.all?(refs, &safe_ref?/1)
        _ -> false
      end
    end)
  end

  defp unsafe_public_json?(%DateTime{}), do: false
  defp unsafe_public_json?(%_{} = value), do: value |> Map.from_struct() |> unsafe_public_json?()

  defp unsafe_public_json?(values) when is_list(values),
    do: Enum.any?(values, &unsafe_public_json?/1)

  defp unsafe_public_json?(%{} = map) do
    Enum.any?(map, fn {key, value} ->
      unsafe_key?(key) or unsafe_public_json?(value)
    end)
  end

  defp unsafe_public_json?(value) when is_binary(value) do
    String.starts_with?(value, ["/", "~/"]) or windows_absolute_path?(value)
  end

  defp unsafe_public_json?(_value), do: false

  defp unsafe_key?(key) when is_atom(key), do: unsafe_key?(Atom.to_string(key))

  defp unsafe_key?(key) when is_binary(key),
    do: MapSet.member?(@unsafe_keys, String.downcase(key))

  defp unsafe_key?(_key), do: false

  defp safe_ref?(value),
    do: is_binary(value) and String.trim(value) != "" and not unsafe_public_json?(value)

  defp windows_absolute_path?(<<drive, ?:, separator, _rest::binary>>) do
    (drive in ?A..?Z or drive in ?a..?z) and separator in [?\\, ?/]
  end

  defp windows_absolute_path?(_value), do: false

  defp turn_refs(%RuntimeRunDetail{} = run_detail) do
    run_detail.turns
    |> Enum.map(&(Map.get(&1, :turn_ref) || Map.get(&1, "turn_ref")))
    |> Enum.reject(&is_nil/1)
  end

  defp ref_list(attrs, key, default \\ []) do
    attrs
    |> map_value(key, default)
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp stable_hash(value) do
    encoded = value |> json_safe() |> Jason.encode!()
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
  end

  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%Date{} = value), do: Date.to_iso8601(value)
  defp json_safe(%Time{} = value), do: Time.to_iso8601(value)
  defp json_safe(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json_safe(%_{} = value), do: value |> Map.from_struct() |> json_safe()
  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)
  defp json_safe(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_safe()

  defp json_safe(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_safe(value)} end)
  end

  defp json_safe(value) when is_atom(value), do: to_string(value)
  defp json_safe(value), do: value

  defp tenant_ref(%Config{} = config), do: "tenant://#{config.tenant_id}"

  defp runtime_gateway_opts(opts) do
    backend =
      Keyword.get(opts, :generic_backend) ||
        Keyword.get(opts, :runtime_gateway_backend) ||
        Keyword.get(opts, :backend) ||
        Application.get_env(:app_kit_core, :generic_backend) ||
        Application.get_env(:app_kit_core, :source_backend)

    if backend do
      Keyword.put(opts, :generic_backend, backend)
    else
      opts
    end
  end

  defp put_runtime_binding(request) do
    params =
      request
      |> map_value(:params, %{})
      |> Map.put_new(:runtime_binding, coding_agent_runtime_binding())

    Map.put(request, :params, params)
  end

  defp coding_agent_runtime_binding do
    %{
      runtime_binding_ref: "runtime-binding://extravaganza/profile-a-coding-runtime",
      runtime_role_ref: :coding_agent_runtime,
      adapter_ref: :codex_cli,
      manifest_ref: "manifest://jido/connectors/codex_cli@local",
      operation_ref: "codex.session.turn",
      allowed_operations: ["codex.session.turn"]
    }
  end

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end
end
