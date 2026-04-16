defmodule Extravaganza.Workflows do
  @moduledoc """
  Product-local workflow commands over AppKit.
  """

  alias AppKit.Core.RunRequest
  alias AppKit.{WorkControl, WorkSurface}
  alias Extravaganza.ProductSurface

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, subject_ref} <- WorkSurface.ingest_subject(context, Map.new(domain_call)),
         {:ok, run_request} <- RunRequest.new(%{subject_ref: subject_ref}) do
      WorkControl.start_run(context, run_request, ProductSurface.work_control_opts(config, opts))
    end
  end
end
