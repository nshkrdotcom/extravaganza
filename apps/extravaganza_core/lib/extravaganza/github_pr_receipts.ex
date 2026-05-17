defmodule Extravaganza.GitHubPrBranchCleanupReceipt do
  @moduledoc false

  alias AppKit.Core.RuntimeSurface.Support

  @statuses [:receipt_recorded, :skipped, :denied, :failed]
  defstruct [
    :effect_ref,
    :tenant_ref,
    :provider,
    :effect,
    :status,
    :repo,
    :branch,
    capability_ids: [],
    pull_numbers: [],
    closed_pull_numbers: [],
    credential_present?: false,
    credential_redeemed?: false,
    provider_request_sent?: false,
    provider_response_received?: false,
    receipt_recorded?: false,
    product_readback_confirmed?: false,
    write_operations: [],
    provider_ids: %{},
    provider_refs: %{},
    counts: %{},
    receipt_refs: %{},
    operation_receipts: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(attrs) do
    with {:ok, attrs} <- Support.normalize(attrs),
         :ok <- Support.reject_forbidden_material(attrs),
         {:ok, effect_ref} <- Support.required_string(attrs, :effect_ref),
         {:ok, provider} <- Support.required_string(attrs, :provider),
         {:ok, effect} <- Support.required_string(attrs, :effect),
         {:ok, status} <- Support.status(attrs, :status, @statuses),
         {:ok, repo} <- Support.required_string(attrs, :repo),
         {:ok, branch} <- Support.required_string(attrs, :branch),
         capability_ids <- string_list(attrs, :capability_ids),
         pull_numbers <- positive_integer_list(attrs, :pull_numbers),
         closed_pull_numbers <- positive_integer_list(attrs, :closed_pull_numbers),
         credential_present? when is_boolean(credential_present?) <-
           Support.boolean(attrs, :credential_present?, false),
         credential_redeemed? when is_boolean(credential_redeemed?) <-
           Support.boolean(attrs, :credential_redeemed?, false),
         provider_request_sent? when is_boolean(provider_request_sent?) <-
           Support.boolean(attrs, :provider_request_sent?, false),
         provider_response_received? when is_boolean(provider_response_received?) <-
           Support.boolean(attrs, :provider_response_received?, false),
         receipt_recorded? when is_boolean(receipt_recorded?) <-
           Support.boolean(attrs, :receipt_recorded?, false),
         product_readback_confirmed? when is_boolean(product_readback_confirmed?) <-
           Support.boolean(attrs, :product_readback_confirmed?, false),
         write_operations <- string_list(attrs, :write_operations),
         provider_ids when is_map(provider_ids) <- Support.optional_map(attrs, :provider_ids, %{}),
         provider_refs when is_map(provider_refs) <-
           Support.optional_map(attrs, :provider_refs, %{}),
         counts when is_map(counts) <- Support.optional_map(attrs, :counts, %{}),
         receipt_refs when is_map(receipt_refs) <- Support.optional_map(attrs, :receipt_refs, %{}),
         operation_receipts <- map_list(attrs, :operation_receipts),
         metadata when is_map(metadata) <- Support.optional_map(attrs, :metadata, %{}) do
      {:ok,
       %__MODULE__{
         effect_ref: effect_ref,
         tenant_ref: Support.string(attrs, :tenant_ref),
         provider: provider,
         effect: effect,
         status: status,
         repo: repo,
         branch: branch,
         capability_ids: capability_ids,
         pull_numbers: pull_numbers,
         closed_pull_numbers: closed_pull_numbers,
         credential_present?: credential_present?,
         credential_redeemed?: credential_redeemed?,
         provider_request_sent?: provider_request_sent?,
         provider_response_received?: provider_response_received?,
         receipt_recorded?: receipt_recorded?,
         product_readback_confirmed?: product_readback_confirmed?,
         write_operations: write_operations,
         provider_ids: provider_ids,
         provider_refs: provider_refs,
         counts: counts,
         receipt_refs: receipt_refs,
         operation_receipts: operation_receipts,
         metadata: metadata
       }}
    else
      _other -> {:error, :invalid_github_pr_branch_cleanup_receipt}
    end
  end

  defp string_list(attrs, key) do
    values = Support.optional_list(attrs, key, [])
    if Enum.all?(values, &is_binary/1), do: values, else: :invalid
  end

  defp map_list(attrs, key) do
    values = Support.optional_list(attrs, key, [])
    if Enum.all?(values, &is_map/1), do: values, else: :invalid
  end

  defp positive_integer_list(attrs, key) do
    values = Support.optional_list(attrs, key, [])
    if Enum.all?(values, &(is_integer(&1) and &1 > 0)), do: values, else: :invalid
  end
end

defmodule Extravaganza.GitHubPrEvidenceReceipt do
  @moduledoc false

  alias AppKit.Core.RuntimeSurface.Support

  @statuses [:receipt_recorded, :skipped, :denied, :failed]
  defstruct [
    :effect_ref,
    :tenant_ref,
    :provider,
    :effect,
    :status,
    :repo,
    :pull_number,
    :head_sha,
    :evidence_ref,
    capability_ids: [],
    credential_present?: false,
    credential_redeemed?: false,
    provider_request_sent?: false,
    provider_response_received?: false,
    receipt_recorded?: false,
    product_readback_confirmed?: false,
    fixture_setup_required?: false,
    write_operations: [],
    provider_ids: %{},
    provider_refs: %{},
    counts: %{},
    receipt_refs: %{},
    operation_receipts: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def new(%__MODULE__{} = value), do: {:ok, value}

  def new(attrs) do
    with {:ok, attrs} <- Support.normalize(attrs),
         :ok <- Support.reject_forbidden_material(attrs),
         {:ok, effect_ref} <- Support.required_string(attrs, :effect_ref),
         {:ok, provider} <- Support.required_string(attrs, :provider),
         {:ok, effect} <- Support.required_string(attrs, :effect),
         {:ok, status} <- Support.status(attrs, :status, @statuses),
         {:ok, repo} <- Support.required_string(attrs, :repo),
         pull_number when pull_number == nil or (is_integer(pull_number) and pull_number > 0) <-
           positive_integer_or_nil(attrs, :pull_number),
         capability_ids <- string_list(attrs, :capability_ids),
         credential_present? when is_boolean(credential_present?) <-
           Support.boolean(attrs, :credential_present?, false),
         credential_redeemed? when is_boolean(credential_redeemed?) <-
           Support.boolean(attrs, :credential_redeemed?, false),
         provider_request_sent? when is_boolean(provider_request_sent?) <-
           Support.boolean(attrs, :provider_request_sent?, false),
         provider_response_received? when is_boolean(provider_response_received?) <-
           Support.boolean(attrs, :provider_response_received?, false),
         receipt_recorded? when is_boolean(receipt_recorded?) <-
           Support.boolean(attrs, :receipt_recorded?, false),
         product_readback_confirmed? when is_boolean(product_readback_confirmed?) <-
           Support.boolean(attrs, :product_readback_confirmed?, false),
         fixture_setup_required? when is_boolean(fixture_setup_required?) <-
           Support.boolean(attrs, :fixture_setup_required?, false),
         write_operations <- string_list(attrs, :write_operations),
         provider_ids when is_map(provider_ids) <- Support.optional_map(attrs, :provider_ids, %{}),
         provider_refs when is_map(provider_refs) <-
           Support.optional_map(attrs, :provider_refs, %{}),
         counts when is_map(counts) <- Support.optional_map(attrs, :counts, %{}),
         receipt_refs when is_map(receipt_refs) <- Support.optional_map(attrs, :receipt_refs, %{}),
         operation_receipts <- map_list(attrs, :operation_receipts),
         metadata when is_map(metadata) <- Support.optional_map(attrs, :metadata, %{}) do
      {:ok,
       %__MODULE__{
         effect_ref: effect_ref,
         tenant_ref: Support.string(attrs, :tenant_ref),
         provider: provider,
         effect: effect,
         status: status,
         repo: repo,
         pull_number: pull_number,
         head_sha: Support.string(attrs, :head_sha),
         evidence_ref: Support.string(attrs, :evidence_ref),
         capability_ids: capability_ids,
         credential_present?: credential_present?,
         credential_redeemed?: credential_redeemed?,
         provider_request_sent?: provider_request_sent?,
         provider_response_received?: provider_response_received?,
         receipt_recorded?: receipt_recorded?,
         product_readback_confirmed?: product_readback_confirmed?,
         fixture_setup_required?: fixture_setup_required?,
         write_operations: write_operations,
         provider_ids: provider_ids,
         provider_refs: provider_refs,
         counts: counts,
         receipt_refs: receipt_refs,
         operation_receipts: operation_receipts,
         metadata: metadata
       }}
    else
      _other -> {:error, :invalid_github_pr_evidence_receipt}
    end
  end

  defp string_list(attrs, key) do
    values = Support.optional_list(attrs, key, [])
    if Enum.all?(values, &is_binary/1), do: values, else: :invalid
  end

  defp map_list(attrs, key) do
    values = Support.optional_list(attrs, key, [])
    if Enum.all?(values, &is_map/1), do: values, else: :invalid
  end

  defp positive_integer_or_nil(attrs, key) do
    case Support.value(attrs, key) do
      nil -> nil
      value when is_integer(value) and value > 0 -> value
      _other -> :invalid
    end
  end
end
