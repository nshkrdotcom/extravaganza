defmodule Extravaganza.Queries do
  @moduledoc """
  Product-local read facade over operator-facing AppKit surfaces.
  """

  alias AppKit.Core.{PageRequest, SortSpec}
  alias AppKit.{OperatorSurface, ReviewSurface, WorkSurface}
  alias Extravaganza.{Config, ProductSurface}

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ []) when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)
    OperatorSurface.run_status(run_ref, attrs, ProductSurface.operator_opts(config, opts))
  end

  @spec operator_queue(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def operator_queue(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, page_request} <- page_request(params, "updated_at", :desc),
         query_opts <- ProductSurface.work_query_opts(config, opts),
         {:ok, page} <- WorkSurface.list_subjects(context, page_request, query_opts),
         {:ok, stats} <- WorkSurface.queue_stats(context, page_request.filters, query_opts) do
      {:ok, %{page: page, stats: stats}}
    end
  end

  @spec pending_reviews(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def pending_reviews(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, page_request} <- page_request(params, "required_by", :asc),
         review_opts <- ProductSurface.operator_opts(config, opts),
         {:ok, page} <- ReviewSurface.list_pending(context, page_request, review_opts) do
      {:ok, %{page: page}}
    end
  end

  defp page_request(params, sort_field, direction)
       when is_map(params) and is_binary(sort_field) do
    PageRequest.new(%{
      limit: page_limit(params),
      cursor: page_cursor(params),
      sort: [%SortSpec{field: sort_field, direction: direction, nulls: :last}]
    })
  end

  defp page_limit(%{"limit" => value}), do: parsed_positive_integer(value, 25)
  defp page_limit(%{limit: value}), do: parsed_positive_integer(value, 25)
  defp page_limit(_params), do: 25

  defp page_cursor(%{"cursor" => value}) when is_binary(value) and value != "", do: value
  defp page_cursor(%{cursor: value}) when is_binary(value) and value != "", do: value
  defp page_cursor(_params), do: nil

  defp parsed_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp parsed_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parsed_positive_integer(_value, default), do: default
end
