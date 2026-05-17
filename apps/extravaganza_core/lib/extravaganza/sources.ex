defmodule Extravaganza.Sources do
  @moduledoc """
  Product-local source intake facade over AppKit source and work surfaces.
  """

  alias AppKit.Core.SubjectRef
  alias AppKit.SourceSurface
  alias AppKit.WorkSurface

  alias Extravaganza.{
    Config,
    ProductPack,
    ProductSurface
  }

  @linear_state_mapping %{
    "submitted" => ["Todo", "Backlog"],
    "retry_submission" => ["Todo"],
    "completed" => ["Done", "Completed"],
    "rejected" => ["Canceled", "Cancelled", "Duplicate"]
  }
  @source_role_ref :issue_tracker

  @spec sync_linear_issues(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_linear_issues(source_page, opts \\ []) when is_map(source_page) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts) do
      SourceSurface.sync_source(
        context,
        @source_role_ref,
        product_source_page(source_page, config),
        ProductSurface.work_query_opts(config, opts)
      )
    end
  end

  @spec sync_linear_issue(map(), keyword()) ::
          {:ok, AppKit.Core.SubjectDetail.t()} | {:error, term()}
  def sync_linear_issue(issue, opts \\ []) when is_map(issue) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         page <- product_source_page(%{issues: [issue]}, config),
         {:ok, result} <-
           SourceSurface.sync_source(
             context,
             @source_role_ref,
             page,
             ProductSurface.work_query_opts(config, opts)
           ),
         {:ok, subject_ref} <- first_subject_ref(result) do
      WorkSurface.get_subject(context, subject_ref, ProductSurface.work_query_opts(config, opts))
    end
  end

  defp product_source_page(source_page, %Config{} = config) do
    %{
      issues: source_issues(source_page),
      page_info: value(source_page, :page_info) || %{has_next_page: false},
      source_binding: source_binding(source_page, config),
      viewer: value(source_page, :viewer)
    }
    |> compact_map()
  end

  defp source_issues(source_page) do
    case value(source_page, :issues) do
      nil -> [source_page]
      issues -> List.wrap(issues)
    end
  end

  defp source_binding(source_page, %Config{} = config) do
    default_binding = %{
      source_binding_id: ProductPack.source_binding_key(config),
      installation_id: config.tenant_id,
      provider: "linear",
      connection_ref: ProductPack.source_binding_key(config),
      state_mapping: @linear_state_mapping
    }

    source_page
    |> value(:source_binding)
    |> case do
      %{} = binding -> Map.merge(default_binding, Map.new(binding))
      _missing -> default_binding
    end
  end

  defp first_subject_ref(%{subjects: [%{subject_ref: %SubjectRef{} = subject_ref} | _rest]}),
    do: {:ok, subject_ref}

  defp first_subject_ref(%{
         "subjects" => [%{"subject_ref" => %SubjectRef{} = subject_ref} | _rest]
       }),
       do: {:ok, subject_ref}

  defp first_subject_ref(_result), do: {:error, :source_sync_no_subject}

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)
  defp value(%{} = map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end
end
