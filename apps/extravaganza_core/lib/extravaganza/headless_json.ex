defmodule Extravaganza.HeadlessJSON do
  @moduledoc """
  Standard JSON envelope for headless task, script, and HTTP adapters.
  """

  @success_schema "extravaganza.headless.response.v1"
  @error_schema "extravaganza.headless.error.v1"
  @execution_route_ref "generic_substrate:v1"

  @forbidden_keys ~w[
    api_key auth_json authorization_header provider_payload raw_secret raw_token
    target_credentials token_file workspace_path local_path raw_provider_payload secret
    lease_token attach_token linear_api_key github_token gh_token openai_api_key
    codex_api_key access_token authorization
  ]

  @secret_value_keys ~w[
    api_key linear_api_key github_token gh_token openai_api_key codex_api_key
    access_token authorization secret token raw_secret raw_token
  ]

  @spec success(atom() | String.t(), term(), map() | keyword()) :: map()
  def success(operation, data, opts \\ []) do
    opts = opts_map(opts)
    secret_values = secret_values(opts)
    data = sanitize(data, secret_values)
    refs = refs(data)

    runtime_profile_ref =
      first_present([Map.get(opts, :runtime_profile_ref), refs["runtime_profile_ref"]])

    %{
      "ok" => true,
      "schema" => @success_schema,
      "operation" => operation_name(operation),
      "trace_id" => trace_id(opts, refs),
      "execution_route_ref" => @execution_route_ref,
      "idempotency_key" => Map.get(opts, :idempotency_key) || refs["idempotency_key"],
      "runtime_profile_ref" => runtime_profile_ref,
      "data" => data,
      "refs" => Map.put(refs, "execution_route_ref", @execution_route_ref),
      "warnings" => List.wrap(Map.get(opts, :warnings, [])),
      "generated_at" => generated_at(opts)
    }
    |> compact()
  end

  @spec error(atom() | String.t(), term(), map() | keyword()) :: map()
  def error(operation, reason, opts \\ []) do
    opts = opts_map(opts)
    secret_values = secret_values(opts)
    error = error_attrs(reason, secret_values)

    %{
      "ok" => false,
      "schema" => @error_schema,
      "operation" => operation_name(operation),
      "trace_id" => trace_id(opts, %{}),
      "execution_route_ref" => @execution_route_ref,
      "error" => error,
      "generated_at" => generated_at(opts)
    }
    |> compact()
  end

  @spec wrap(
          atom() | String.t(),
          {:ok, term()} | {:error, term()},
          (term() -> term()),
          keyword() | map()
        ) ::
          map()
  def wrap(operation, result, presenter, opts \\ [])

  def wrap(operation, {:ok, value}, presenter, opts) when is_function(presenter, 1) do
    success(operation, presenter.(value), opts)
  end

  def wrap(operation, {:error, reason}, _presenter, opts), do: error(operation, reason, opts)

  @spec refs(term()) :: map()
  def refs(data) do
    %{}
    |> put_ref("subject_ref", first_path(data, subject_paths()))
    |> put_ref("run_ref", first_path(data, run_paths()))
    |> put_ref("workflow_ref", first_path(data, workflow_paths()))
    |> put_ref("runtime_profile_ref", first_path(data, runtime_profile_paths()))
    |> put_ref("authority_ref", first_path(data, authority_paths()))
    |> put_ref("decision_ref", first_path(data, decision_paths()))
    |> put_ref("connector_manifest_ref", first_path(data, manifest_paths()))
    |> put_ref("capability_negotiation_ref", first_path(data, negotiation_paths()))
    |> put_ref("lower_request_ref", first_path(data, lower_request_paths()))
    |> put_ref("lower_receipt_ref", first_path(data, lower_receipt_paths()))
    |> put_ref("lower_denial_ref", first_path(data, lower_denial_paths()))
    |> put_ref("source_publication_ref", first_path(data, source_publication_paths()))
    |> put_ref("evidence_chain_ref", first_path(data, evidence_chain_paths()))
    |> put_ref("event_page_ref", first_path(data, event_page_paths()))
    |> put_ref("idempotency_key", first_path(data, idempotency_paths()))
  end

  @spec sanitize(term()) :: term()
  def sanitize(value), do: sanitize(value, [])

  @spec sanitize(term(), [String.t()]) :: term()
  def sanitize(%DateTime{} = value, _secret_values), do: DateTime.to_iso8601(value)
  def sanitize(%NaiveDateTime{} = value, _secret_values), do: NaiveDateTime.to_iso8601(value)
  def sanitize(%Date{} = value, _secret_values), do: Date.to_iso8601(value)
  def sanitize(%Time{} = value, _secret_values), do: Time.to_iso8601(value)

  def sanitize(%_{} = value, secret_values),
    do: value |> Map.from_struct() |> sanitize(secret_values)

  def sanitize(%{} = map, secret_values) do
    map
    |> Enum.reject(fn {key, _value} -> forbidden_key?(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), sanitize(value, secret_values)} end)
  end

  def sanitize(values, secret_values) when is_list(values),
    do: Enum.map(values, &sanitize(&1, secret_values))

  def sanitize(value, secret_values) when is_tuple(value),
    do: value |> Tuple.to_list() |> sanitize(secret_values)

  def sanitize(nil, _secret_values), do: nil
  def sanitize(true, _secret_values), do: true
  def sanitize(false, _secret_values), do: false

  def sanitize(value, secret_values) when is_binary(value) do
    value = redact_secret_values(value, secret_values)

    if absolute_path?(value) and not safe_route_path?(value), do: "[redacted-path]", else: value
  end

  def sanitize(value, _secret_values) when is_atom(value), do: Atom.to_string(value)
  def sanitize(value, _secret_values), do: value

  defp absolute_path?(value) do
    Path.type(value) == :absolute
  rescue
    ArgumentError -> false
  end

  defp safe_route_path?(value) do
    String.starts_with?(value, ["/api/", "/queue", "/operator-console", "/reviews", "/subjects/"]) or
      value == "/"
  end

  defp subject_paths do
    [
      ["data", "proof", "subject_ref"],
      ["proof", "subject_ref"],
      ["data", "subject_ref"],
      ["data", "runtime_row", "subject_ref"],
      ["subject_ref"],
      ["runtime_row", "subject_ref"]
    ]
  end

  defp run_paths do
    [
      ["data", "proof", "run_ref"],
      ["proof", "run_ref"],
      ["data", "run_ref"],
      ["data", "runtime_row", "run_ref"],
      ["run_ref"],
      ["runtime_row", "run_ref"]
    ]
  end

  defp workflow_paths do
    [
      ["data", "proof", "workflow_ref"],
      ["proof", "workflow_ref"],
      ["data", "runtime_row", "workflow_ref"],
      ["runtime_row", "workflow_ref"],
      ["workflow_ref"]
    ]
  end

  defp runtime_profile_paths do
    [
      ["data", "proof", "runtime_profile_ref"],
      ["proof", "runtime_profile_ref"],
      ["runtime_profile_ref"],
      ["data", "runtime_profile_ref"],
      ["data", "runtime_row", "extensions", "governance", "runtime_profile_ref"],
      ["runtime_row", "extensions", "governance", "runtime_profile_ref"],
      ["data", "governance", "runtime_profile_ref"],
      ["governance", "runtime_profile_ref"]
    ]
  end

  defp authority_paths do
    [
      ["data", "proof", "authority_ref"],
      ["proof", "authority_ref"],
      ["data", "governance", "authority_ref"],
      ["governance", "authority_ref"],
      ["data", "runtime_row", "extensions", "governance", "authority_ref"],
      ["runtime_row", "extensions", "governance", "authority_ref"]
    ]
  end

  defp decision_paths do
    [
      ["data", "proof", "decision_ref"],
      ["proof", "decision_ref"],
      ["data", "governance", "decision_ref"],
      ["governance", "decision_ref"],
      ["data", "runtime_row", "extensions", "governance", "decision_ref"],
      ["runtime_row", "extensions", "governance", "decision_ref"]
    ]
  end

  defp manifest_paths do
    [
      ["data", "proof", "connector_manifest_ref"],
      ["proof", "connector_manifest_ref"],
      ["data", "governance", "connector_manifest_ref"],
      ["governance", "connector_manifest_ref"],
      ["data", "runtime_row", "extensions", "governance", "connector_manifest_ref"],
      ["runtime_row", "extensions", "governance", "connector_manifest_ref"]
    ]
  end

  defp negotiation_paths do
    [
      ["data", "proof", "capability_negotiation_ref"],
      ["proof", "capability_negotiation_ref"],
      ["data", "governance", "capability_negotiation_ref"],
      ["governance", "capability_negotiation_ref"],
      ["data", "runtime_row", "extensions", "governance", "capability_negotiation_ref"],
      ["runtime_row", "extensions", "governance", "capability_negotiation_ref"]
    ]
  end

  defp lower_request_paths do
    [
      ["data", "proof", "lower_request_ref"],
      ["proof", "lower_request_ref"],
      ["data", "lower", "lower_request_ref"],
      ["lower", "lower_request_ref"],
      ["data", "runtime_row", "extensions", "lower_envelope", "lower_request_ref"],
      ["runtime_row", "extensions", "lower_envelope", "lower_request_ref"]
    ]
  end

  defp lower_receipt_paths do
    [
      ["data", "proof", "lower_receipt_ref"],
      ["proof", "lower_receipt_ref"],
      ["data", "lower_receipt", "lower_receipt_ref"],
      ["lower_receipt", "lower_receipt_ref"],
      ["data", "runtime_row", "extensions", "lower_receipt", "lower_receipt_ref"],
      ["runtime_row", "extensions", "lower_receipt", "lower_receipt_ref"]
    ]
  end

  defp lower_denial_paths do
    [
      ["data", "lower", "lower_denial_ref"],
      ["lower", "lower_denial_ref"],
      ["data", "runtime_row", "extensions", "lower_envelope", "lower_denial_ref"],
      ["runtime_row", "extensions", "lower_envelope", "lower_denial_ref"]
    ]
  end

  defp source_publication_paths do
    [
      ["data", "proof", "source_publication_ref"],
      ["proof", "source_publication_ref"],
      ["data", "source_publication_receipt_ref"],
      ["data", "source_publication_ref"],
      ["source_publication_ref"],
      ["data", "source_publication", "source_publication_receipt_ref"],
      ["data", "source_publication", "source_publication_ref"],
      ["source_publication", "source_publication_receipt_ref"],
      ["source_publication", "source_publication_ref"],
      [
        "data",
        "runtime_row",
        "extensions",
        "source_publication",
        "source_publication_receipt_ref"
      ],
      ["runtime_row", "extensions", "source_publication", "source_publication_receipt_ref"]
    ]
  end

  defp evidence_chain_paths do
    [
      ["data", "proof", "evidence_chain_ref"],
      ["proof", "evidence_chain_ref"],
      ["data", "evidence_chain_ref"],
      ["evidence_chain_ref"]
    ]
  end

  defp event_page_paths do
    [
      ["data", "proof", "event_page_ref"],
      ["proof", "event_page_ref"],
      ["data", "event_page_ref"],
      ["event_page_ref"]
    ]
  end

  defp idempotency_paths do
    [
      ["data", "idempotency_key"],
      ["idempotency_key"],
      ["data", "data", "idempotency_key"]
    ]
  end

  defp first_path(data, paths), do: Enum.find_value(paths, &path_value(data, &1))

  defp path_value(data, path) do
    Enum.reduce_while(path, data, fn key, acc ->
      case fetch(acc, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp fetch(%{} = map, key), do: string_or_atom_key_value(map, key)
  defp fetch(_value, _key), do: nil

  defp put_ref(refs, _key, nil), do: refs
  defp put_ref(refs, _key, ""), do: refs
  defp put_ref(refs, key, value) when is_binary(value), do: Map.put(refs, key, value)
  defp put_ref(refs, key, value), do: Map.put(refs, key, to_string(value))

  defp error_attrs(:runtime_projection_not_found, _secret_values) do
    %{
      "code" => "projection_unavailable",
      "message" => "runtime projection is not available for this run",
      "class" => "readback_unavailable",
      "retryable" => true,
      "missing_refs" => ["projection_ref"]
    }
  end

  defp error_attrs(:unavailable, _secret_values) do
    %{
      "code" => "unavailable",
      "message" => "headless surface is unavailable",
      "class" => "surface_unavailable",
      "retryable" => true,
      "missing_refs" => []
    }
  end

  defp error_attrs(:bad_request, _secret_values) do
    %{
      "code" => "bad_request",
      "message" => "request is missing required headless parameters",
      "class" => "invalid_request",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:not_found, _secret_values) do
    %{
      "code" => "not_found",
      "message" => "headless resource was not found",
      "class" => "not_found",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:method_not_allowed, _secret_values) do
    %{
      "code" => "method_not_allowed",
      "message" => "HTTP method is not allowed for this headless route",
      "class" => "invalid_request",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:invalid_action, _secret_values) do
    %{
      "code" => "invalid_action",
      "message" => "requested action is not supported by this headless surface",
      "class" => "invalid_request",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:action_denied, _secret_values) do
    %{
      "code" => "action_denied",
      "message" => "headless action was denied by authority",
      "class" => "denied",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:unauthorized_lower_read, _secret_values) do
    %{
      "code" => "unauthorized_lower_read",
      "message" => "lower read is not authorized for this request",
      "class" => "unauthorized",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:snapshot_timeout, _secret_values) do
    %{
      "code" => "snapshot_timeout",
      "message" => "headless snapshot timed out",
      "class" => "timeout",
      "retryable" => true,
      "missing_refs" => []
    }
  end

  defp error_attrs(:archived, _secret_values) do
    %{
      "code" => "archived",
      "message" => "headless resource is archived",
      "class" => "archived",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(:internal_error, _secret_values) do
    %{
      "code" => "internal_error",
      "message" => "internal headless error",
      "class" => "internal_error",
      "retryable" => false,
      "missing_refs" => []
    }
  end

  defp error_attrs(%AppKit.Core.SurfaceError{} = error, secret_values) do
    code = reason_code(error.code)
    {class, retryable?, missing_refs} = surface_error_contract(error, code)

    %{
      "code" => code,
      "message" => error.message,
      "class" => class,
      "retryable" => retryable?,
      "missing_refs" => missing_refs,
      "details" =>
        error.details
        |> Map.new()
        |> put_optional_detail("cause_ref", error.cause_ref)
        |> sanitize(secret_values)
    }
    |> compact_error()
  end

  defp error_attrs({:live_surface_dependency_failed, app, reason}, secret_values) do
    classified_error(
      "live_surface_dependency_failed",
      %{"app" => app, "reason" => inspect(reason)},
      secret_values
    )
  end

  defp error_attrs({:missing_workflow_file, path, reason}, secret_values) do
    classified_error(
      "missing_workflow_file",
      %{"path" => path, "reason" => reason},
      secret_values
    )
  end

  defp error_attrs({:operator_ack_required, details}, secret_values) do
    %{
      "code" => "operator_ack_required",
      "message" =>
        "operator acknowledgement is required before this headless command may trigger side effects",
      "class" => "operator_ack_required",
      "retryable" => false,
      "missing_refs" => ["operator_acknowledgement"],
      "details" => sanitize(details, secret_values)
    }
  end

  defp error_attrs({reason, detail}, secret_values) do
    reason
    |> reason_code()
    |> classified_error(error_details(detail), secret_values)
  end

  defp error_attrs(%{} = reason, secret_values) do
    code = map_value(reason, "code") || "internal_error"
    details = Map.drop(reason, ["code", :code, "message", :message])
    message = map_value(reason, "message")

    code
    |> classified_error(details, secret_values)
    |> maybe_replace_message(message)
  end

  defp error_attrs(reason, secret_values) do
    reason
    |> reason_code()
    |> classified_error(%{}, secret_values)
  end

  defp classified_error(code, details, secret_values) do
    {message, class, retryable?, missing_refs} = classified_attrs(code)

    %{
      "code" => code,
      "message" => message,
      "class" => class,
      "retryable" => retryable?,
      "missing_refs" => missing_refs,
      "details" => details |> Map.new() |> sanitize(secret_values)
    }
    |> compact_error()
  end

  defp classified_attrs("live_product_path_required") do
    {"live provider dispatch requires --live-product-path", "missing_live_prerequisite", false,
     ["live_product_path"]}
  end

  defp classified_attrs("requires_live_product_path") do
    {"live provider dispatch requires --live-product-path", "missing_live_prerequisite", false,
     ["live_product_path"]}
  end

  defp classified_attrs("missing_live_linear_publication_issue") do
    {"live Linear publication requires a provider issue ref", "missing_live_prerequisite", false,
     ["linear_issue_ref"]}
  end

  defp classified_attrs("credential_stdin_empty") do
    {"credential input on stdin was empty", "missing_credential", false, ["provider_credential"]}
  end

  defp classified_attrs("credential_not_supplied_to_product_command") do
    {"provider credential was not supplied to the product command", "missing_credential", false,
     ["provider_credential"]}
  end

  defp classified_attrs("missing_linear_api_token") do
    {"Linear provider credential was not supplied", "missing_credential", false,
     ["provider_credential"]}
  end

  defp classified_attrs("missing_provider_credential") do
    {"provider credential was not supplied", "missing_credential", false, ["provider_credential"]}
  end

  defp classified_attrs("invalid_workflow_config") do
    {"workflow profile is invalid", "invalid_profile", false, ["workflow_profile"]}
  end

  defp classified_attrs("workflow_front_matter_not_a_map") do
    {"workflow front matter is invalid", "invalid_profile", false, ["workflow_profile"]}
  end

  defp classified_attrs("workflow_parse_error") do
    {"workflow profile could not be parsed", "invalid_profile", false, ["workflow_profile"]}
  end

  defp classified_attrs("missing_workflow_file") do
    {"workflow profile file is missing", "invalid_profile", false, ["workflow_file"]}
  end

  defp classified_attrs("unsupported_tracker_kind") do
    {"workflow tracker kind is not supported", "invalid_profile", false, ["workflow_profile"]}
  end

  defp classified_attrs("incompatible_product_runtime_profile") do
    {"runtime profile is not compatible with this product", "invalid_profile", false,
     ["runtime_profile_ref"]}
  end

  defp classified_attrs("unsupported_runtime_profile_change") do
    {"runtime profile change is not supported by this product", "invalid_profile", false,
     ["runtime_profile_ref"]}
  end

  defp classified_attrs("linear_graphql_variables_json_must_decode_to_object") do
    {"Linear GraphQL variables JSON must decode to an object", "invalid_request", false,
     ["variables_json"]}
  end

  defp classified_attrs("invalid_linear_graphql_variables_json") do
    {"Linear GraphQL variables JSON is invalid", "invalid_request", false, ["variables_json"]}
  end

  defp classified_attrs("provider_denied") do
    {"provider request was denied before completion", "provider_denial", false, []}
  end

  defp classified_attrs("provider_authority_denied") do
    {"provider request was denied by authority", "provider_denial", false, []}
  end

  defp classified_attrs("policy_denied") do
    {"provider request was denied by policy", "provider_denial", false, []}
  end

  defp classified_attrs("provider_failed") do
    {"provider request failed after dispatch", "provider_error", true, []}
  end

  defp classified_attrs("provider_error") do
    {"provider request failed", "provider_error", true, []}
  end

  defp classified_attrs("provider_timeout") do
    {"provider request timed out", "provider_error", true, []}
  end

  defp classified_attrs("live_surface_dependency_failed") do
    {"live provider dependency could not be started", "app_not_started", true,
     ["live_surface_dependency"]}
  end

  defp classified_attrs("startup_failed") do
    {"headless application startup failed", "app_not_started", true, ["application"]}
  end

  defp classified_attrs("app_not_started") do
    {"required application is not started", "app_not_started", true, ["application"]}
  end

  defp classified_attrs("temporal_substrate_unavailable") do
    {"Temporal substrate is unavailable", "app_not_started", true, ["temporal_substrate"]}
  end

  defp classified_attrs("lower_run_posture_required") do
    {"shutdown requires lower-run posture proof", "shutdown_precondition", false,
     ["lower_run_posture"]}
  end

  defp classified_attrs("active_lower_runs_present") do
    {"shutdown is blocked while active lower runs are present", "shutdown_precondition", false,
     ["lower_run_refs"]}
  end

  defp classified_attrs("runtime_installation_not_provisioned") do
    {"runtime installation is not provisioned", "product_host_unavailable", true,
     ["runtime_installation_ref"]}
  end

  defp classified_attrs(code) do
    {String.replace(code, "_", " "), "headless_error", false, []}
  end

  defp surface_error_contract(%AppKit.Core.SurfaceError{} = error, code) do
    cond do
      code in ["provider_denied", "provider_authority_denied", "policy_denied"] or
          error.kind == :authorization ->
        {"provider_denial", false, []}

      String.starts_with?(code, "provider_") ->
        {"provider_error", surface_retryable?(error), []}

      code in [
        "invalid_workflow_config",
        "incompatible_product_runtime_profile",
        "unsupported_runtime_profile_change"
      ] ->
        {"invalid_profile", error.retryable == true, elem(classified_attrs(code), 3)}

      true ->
        {surface_kind(error.kind), error.retryable == true, []}
    end
  end

  defp surface_retryable?(%AppKit.Core.SurfaceError{retryable: retryable, kind: kind}) do
    retryable == true or kind == :transient
  end

  defp surface_kind(nil), do: "surface_error"
  defp surface_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
  defp surface_kind(kind) when is_binary(kind), do: kind
  defp surface_kind(_kind), do: "surface_error"

  defp error_details(%{} = detail), do: detail
  defp error_details(detail), do: %{"detail" => detail}

  defp maybe_replace_message(error, message) when is_binary(message) and message != "",
    do: Map.put(error, "message", message)

  defp maybe_replace_message(error, _message), do: error

  defp reason_code(reason) when is_binary(reason), do: reason
  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code(_reason), do: "internal_error"

  defp map_value(%{} = map, key), do: string_or_atom_key_value(map, key)

  defp put_optional_detail(details, _key, nil), do: details
  defp put_optional_detail(details, _key, ""), do: details
  defp put_optional_detail(details, key, value), do: Map.put(details, key, value)

  defp compact_error(%{} = map) do
    Map.reject(map, fn
      {"details", value} -> value in [nil, %{}, []]
      {_key, value} -> is_nil(value)
    end)
  end

  defp string_or_atom_key_value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> atom_key_value(map, key)
    end
  end

  defp atom_key_value(map, key) do
    Enum.find_value(map, &matching_atom_key_value(&1, key))
  end

  defp matching_atom_key_value({atom_key, value}, key) when is_atom(atom_key) do
    if Atom.to_string(atom_key) == key, do: value
  end

  defp matching_atom_key_value(_entry, _key), do: nil

  defp trace_id(opts, refs) do
    Map.get(opts, :trace_id) ||
      refs["trace_id"] ||
      "trace:extravaganza:headless:#{System.unique_integer([:positive])}"
  end

  defp generated_at(%{generated_at: generated_at}) when is_binary(generated_at), do: generated_at

  defp generated_at(_opts),
    do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp operation_name(operation), do: operation |> to_string() |> String.replace("_", "_")

  defp opts_map(opts) when is_map(opts), do: Map.new(opts)
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp secret_values(opts) do
    opts
    |> Enum.filter(fn {key, value} -> secret_value_key?(key) and redaction_value?(value) end)
    |> Enum.map(fn {_key, value} -> value end)
    |> Enum.uniq()
  end

  defp secret_value_key?(key), do: (key |> to_string() |> String.downcase()) in @secret_value_keys

  defp redaction_value?(value), do: is_binary(value) and byte_size(String.trim(value)) >= 4

  defp redact_secret_values(value, secret_values) do
    Enum.reduce(secret_values, value, fn secret, acc ->
      String.replace(acc, secret, "[REDACTED]")
    end)
  end

  defp forbidden_key?(key), do: (key |> to_string() |> String.downcase()) in @forbidden_keys

  defp first_present(values) do
    Enum.find(values, fn value -> is_binary(value) and String.trim(value) != "" end)
  end

  defp compact(%{} = map), do: Map.reject(map, fn {_key, value} -> value in [nil, %{}, []] end)
end
