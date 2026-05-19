defmodule Extravaganza.SymphonyWorkflowImport.Document do
  @moduledoc false

  @workflow_file_name "WORKFLOW.md"

  @type loaded_workflow :: %{
          path: Path.t(),
          config: map(),
          prompt: String.t(),
          prompt_template: String.t()
        }

  @spec default_workflow_path(keyword() | map()) :: Path.t()
  def default_workflow_path(opts \\ []) do
    opts
    |> opt(:cwd, File.cwd!())
    |> Path.join(@workflow_file_name)
  end

  @spec workflow_path(keyword() | map()) :: Path.t()
  def workflow_path(opts) do
    case opt(opts, :workflow_path) || opt(opts, :workflow) do
      path when is_binary(path) and path != "" -> Path.expand(path, opt(opts, :cwd, File.cwd!()))
      _other -> default_workflow_path(opts)
    end
  end

  @spec load(keyword() | map()) :: {:ok, loaded_workflow()} | {:error, term()}
  def load(opts \\ []) do
    path = workflow_path(opts)

    case File.read(path) do
      {:ok, content} ->
        parse(content, path)

      {:error, reason} ->
        {:error, {:missing_workflow_file, path, reason}}
    end
  end

  @spec parse(String.t(), Path.t()) :: {:ok, loaded_workflow()} | {:error, term()}
  def parse(content, path) when is_binary(content) do
    {front_matter_lines, prompt_lines} = split_front_matter(content)

    case front_matter_yaml_to_map(front_matter_lines) do
      {:ok, front_matter} ->
        prompt = prompt_lines |> Enum.join("\n") |> String.trim()

        {:ok,
         %{
           path: path,
           config: front_matter,
           prompt: prompt,
           prompt_template: prompt
         }}

      {:error, :workflow_front_matter_not_a_map} ->
        {:error, :workflow_front_matter_not_a_map}

      {:error, reason} ->
        {:error, {:workflow_parse_error, reason}}
    end
  end

  defp split_front_matter(content) do
    lines = split_lines(content)

    case lines do
      ["---" | tail] ->
        {front, rest} = Enum.split_while(tail, &(&1 != "---"))

        case rest do
          ["---" | prompt_lines] -> {front, prompt_lines}
          _missing_close -> {front, []}
        end

      _other ->
        {[], lines}
    end
  end

  defp front_matter_yaml_to_map([]), do: {:ok, %{}}

  defp front_matter_yaml_to_map(lines) do
    yaml = Enum.join(lines, "\n")

    if String.trim(yaml) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml) do
        {:ok, decoded} when is_map(decoded) -> {:ok, normalize_keys(decoded)}
        {:ok, _decoded} -> {:error, :workflow_front_matter_not_a_map}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp split_lines(content), do: split_lines(content, "", [])

  defp split_lines(<<>>, current, lines), do: Enum.reverse([current | lines])

  defp split_lines(<<"\r\n", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<"\n", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<"\r", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<char::utf8, rest::binary>>, current, lines) do
    split_lines(rest, current <> <<char::utf8>>, lines)
  end

  defp normalize_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), normalize_keys(nested)} end)
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) || default
  end

  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
