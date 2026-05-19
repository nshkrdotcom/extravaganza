defmodule Extravaganza.HeadlessFixtures.LinearSource do
  @moduledoc """
  Product-owned deterministic Linear-shaped fixtures for headless commands.

  These fixtures preserve the public Extravaganza example vocabulary while
  deriving their source kind and workflow role contract from the product pack.
  """

  alias Extravaganza.{Config, ProductPack}

  @config_override_keys [
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
    :operator_surface_enabled?,
    :app_kit_backends
  ]

  @spec contract(keyword() | map()) :: map()
  def contract(opts \\ []) do
    config = fixture_config(opts)

    %{
      source_kind: config.linear_source_kind,
      workflow_role_refs: ProductPack.workflow_role_refs(config)
    }
  end

  @spec start_subject(keyword() | map()) :: map()
  def start_subject(opts \\ []), do: start_subject(opts, &unique_suffix/0)

  @spec start_subject(keyword() | map(), (-> String.t())) :: map()
  def start_subject(opts, unique_fun) when is_function(unique_fun, 0) do
    config = fixture_config(opts)
    issue_id = option(opts, :issue_id) || "HEADLESS-#{unique_fun.()}"
    title = option(opts, :title) || "Headless deterministic start #{issue_id}"
    description = option(opts, :description) || "Admitted by the headless product command path."

    %{
      external_ref: "linear:#{issue_id}",
      title: title,
      description: description,
      source_kind: config.linear_source_kind,
      payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo"
      },
      normalized_payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo",
        "labels" => ["headless", "deterministic"]
      }
    }
  end

  @spec same_run_subject(keyword() | map()) :: map()
  def same_run_subject(opts \\ []), do: same_run_subject(opts, &unique_suffix/0)

  @spec same_run_subject(keyword() | map(), (-> String.t())) :: map()
  def same_run_subject(opts, unique_fun) when is_function(unique_fun, 0) do
    config = fixture_config(opts)
    issue_id = option(opts, :issue_id) || "SMOKE-#{unique_fun.()}"
    title = option(opts, :title) || "Same-run deterministic smoke #{issue_id}"
    description = option(opts, :description) || "Deterministic same-run headless smoke."

    %{
      external_ref: "linear:#{issue_id}",
      title: title,
      description: description,
      source_kind: config.linear_source_kind,
      payload: %{"issue_id" => issue_id, "identifier" => issue_id, "state" => "Todo"},
      normalized_payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo",
        "labels" => ["headless", "same-run", "deterministic"]
      }
    }
  end

  @spec source_issue(keyword() | map()) :: map()
  def source_issue(opts \\ []), do: source_issue(opts, &unique_suffix/0)

  @spec source_issue(keyword() | map(), (-> String.t())) :: map()
  def source_issue(opts, unique_fun) when is_function(unique_fun, 0) do
    issue_id = option(opts, :issue_id) || "HEADLESS-#{unique_fun.()}"
    title = option(opts, :title) || "Headless deterministic source #{issue_id}"
    description = option(opts, :description) || "Admitted by the headless source command path."

    %{
      id: issue_id,
      identifier: issue_id,
      title: title,
      description: description,
      state: %{name: "Todo", type: "unstarted"},
      labels: ["headless", "deterministic"],
      url: "https://linear.app/example/issue/#{issue_id}",
      updated_at: option(opts, :now) || current_timestamp()
    }
  end

  defp fixture_config(opts) do
    opts
    |> config_overrides()
    |> Config.load()
  end

  defp config_overrides(opts) do
    attrs = opts_map(opts)

    @config_override_keys
    |> Enum.reduce([], fn key, acc ->
      case option_from_attrs(attrs, key) do
        nil -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
  end

  defp option(opts, key), do: opts |> opts_map() |> option_from_attrs(key)

  defp option_from_attrs(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp opts_map(opts) when is_map(opts), do: opts
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp current_timestamp do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp unique_suffix do
    "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
  end
end
