defmodule Extravaganza.Queries do
  @moduledoc """
  Product-local read facade over operator-facing AppKit surfaces.
  """

  alias AppKit.Core.{PageRequest, SortSpec}
  alias AppKit.{OperatorSurface, WorkSurface}
  alias Extravaganza.{Config, ProductSurface}

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ []) when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)
    OperatorSurface.run_status(run_ref, attrs, ProductSurface.operator_opts(config, opts))
  end

  @spec operator_queue(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def operator_queue(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, page_request} <- queue_page_request(params),
         query_opts <- ProductSurface.work_query_opts(config, opts),
         {:ok, page} <- WorkSurface.list_subjects(context, page_request, query_opts),
         {:ok, stats} <- WorkSurface.queue_stats(context, page_request.filters, query_opts) do
      {:ok, %{page: page, stats: stats}}
    end
  end

  defp queue_page_request(params) when is_map(params) do
    PageRequest.new(%{
      limit: queue_limit(params),
      cursor: queue_cursor(params),
      sort: [%SortSpec{field: "updated_at", direction: :desc, nulls: :last}]
    })
  end

  defp queue_limit(%{"limit" => value}), do: parsed_positive_integer(value, 25)
  defp queue_limit(%{limit: value}), do: parsed_positive_integer(value, 25)
  defp queue_limit(_params), do: 25

  defp queue_cursor(%{"cursor" => value}) when is_binary(value) and value != "", do: value
  defp queue_cursor(%{cursor: value}) when is_binary(value) and value != "", do: value
  defp queue_cursor(_params), do: nil

  defp parsed_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp parsed_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp parsed_positive_integer(_value, default), do: default
end
