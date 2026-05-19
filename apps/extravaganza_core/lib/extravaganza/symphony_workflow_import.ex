defmodule Extravaganza.SymphonyWorkflowImport do
  @moduledoc """
  Product-safe importer for Symphony-style `WORKFLOW.md` files.

  The importer preserves Symphony's file/front-matter/config behavior without
  reading ambient OS environment variables. Callers must provide an explicit
  env map when `$VAR` indirection should be resolved.
  """

  alias Extravaganza.SymphonyWorkflowImport.{
    ConfigNormalizer,
    Document,
    ReloadCache,
    RuntimeProfile,
    Validation
  }

  @solid_render_opts [strict_variables: true, strict_filters: true]

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @type loaded_workflow :: %{
          path: Path.t(),
          config: map(),
          prompt: String.t(),
          prompt_template: String.t()
        }

  @spec default_workflow_path(keyword() | map()) :: Path.t()
  def default_workflow_path(opts \\ []), do: Document.default_workflow_path(opts)

  @spec load(keyword() | map()) :: {:ok, loaded_workflow()} | {:error, term()}
  def load(opts \\ []), do: Document.load(opts)

  @spec profile(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def profile(opts \\ []) do
    with {:ok, loaded} <- Document.load(opts),
         {:ok, config} <- ConfigNormalizer.normalized_config(loaded, ConfigNormalizer.env(opts)) do
      future_work_policy = RuntimeProfile.future_work_policy(config, loaded)

      {:ok,
       %{
         "source" => "symphony_workflow",
         "workflow" => %{
           "path" => loaded.path,
           "prompt_template" => loaded.prompt_template,
           "prompt_hash" => RuntimeProfile.prompt_hash(loaded.prompt_template)
         },
         "config" => config,
         "future_work_policy" => future_work_policy,
         "runtime_policy_config" =>
           RuntimeProfile.runtime_policy_config(config, future_work_policy),
         "runtime_profile" => RuntimeProfile.runtime_profile(config),
         "app_kit_runtime_profile" => RuntimeProfile.app_kit_runtime_profile(config, loaded),
         "validation" => Validation.validation_summary(config)
       }}
    end
  end

  @spec validate(keyword() | map()) :: :ok | {:error, term()}
  def validate(opts \\ []) do
    with {:ok, profile} <- profile(opts) do
      Validation.validate_profile(profile)
    end
  end

  @spec render_prompt(keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def render_prompt(opts \\ []) do
    with {:ok, loaded} <- Document.load(opts) do
      loaded.prompt_template
      |> default_prompt()
      |> render_solid_prompt(%{
        "attempt" => opt(opts, :attempt),
        "issue" => opts |> opt(:issue, %{}) |> to_solid_value(),
        "workflow" => %{
          "path" => loaded.path,
          "config" => loaded.config,
          "prompt_hash" => RuntimeProfile.prompt_hash(loaded.prompt_template)
        }
      })
    end
  end

  @spec reload(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def reload(opts \\ []) do
    ReloadCache.reload(opts, profile(opts))
  end

  @spec reload_status(keyword() | map()) :: map()
  def reload_status(opts \\ []), do: ReloadCache.reload_status(opts)

  @spec runtime_policy_config_from_cache(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def runtime_policy_config_from_cache(opts \\ []),
    do: ReloadCache.runtime_policy_config_from_cache(opts)

  @spec record_runtime_profile_apply(map(), keyword() | map()) :: :ok | {:error, term()}
  def record_runtime_profile_apply(reload, opts \\ []),
    do: ReloadCache.record_runtime_profile_apply(reload, opts)

  defp render_solid_prompt(template, assigns) do
    with {:ok, parsed} <- parse_solid_template(template) do
      try do
        rendered =
          parsed
          |> Solid.render!(assigns, @solid_render_opts)
          |> IO.iodata_to_binary()

        {:ok, rendered}
      rescue
        error -> {:error, {:template_render_error, Exception.message(error)}}
      end
    end
  end

  defp parse_solid_template(template) do
    {:ok, Solid.parse!(template)}
  rescue
    error -> {:error, {:template_parse_error, Exception.message(error)}}
  end

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "", do: @default_prompt_template, else: prompt
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_value()

  defp to_solid_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), to_solid_value(nested)} end)
  end

  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) || default
  end

  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
