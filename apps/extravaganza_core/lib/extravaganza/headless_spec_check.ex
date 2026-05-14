defmodule Extravaganza.HeadlessSpecCheck do
  @moduledoc """
  Static check for the product-owned headless public surface.

  The check ports the intent of Symphony's `specs.check` into Extravaganza
  product tooling: public functions in the configured headless API and adapter
  files need an adjacent `@spec`, an adjacent `@impl`, or an explicit
  contract-test exemption.
  """

  @type finding :: %{
          file: String.t(),
          module: String.t(),
          name: atom(),
          arity: non_neg_integer(),
          line: pos_integer()
        }

  @default_path_patterns [
    "apps/extravaganza_core/lib/extravaganza/headless*.ex",
    "apps/extravaganza_core/lib/extravaganza/live_agent_loop_receipt.ex",
    "apps/extravaganza_core/lib/extravaganza/operators.ex",
    "apps/extravaganza_core/lib/extravaganza/product_host.ex",
    "apps/extravaganza_core/lib/extravaganza/product_surface.ex",
    "apps/extravaganza_core/lib/extravaganza/queries.ex",
    "apps/extravaganza_core/lib/extravaganza/reviews.ex",
    "apps/extravaganza_core/lib/extravaganza/sources.ex",
    "apps/extravaganza_core/lib/extravaganza/workflows.ex",
    "apps/extravaganza_core/lib/extravaganza/presenters/*.ex",
    "apps/extravaganza_core/lib/mix/tasks/extravaganza.headless.ex",
    "apps/extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex",
    "apps/extravaganza_web/lib/extravaganza_web/controllers/page_controller.ex",
    "apps/extravaganza_web/lib/extravaganza_web/headless_server.ex",
    "apps/extravaganza_web/lib/extravaganza_web/observability_updates.ex",
    "apps/extravaganza_web/lib/mix/tasks/extravaganza.headless.web.ex"
  ]

  @default_exemptions_path "config/headless_spec_contract_exemptions.txt"

  @spec default_paths() :: [Path.t()]
  def default_paths, do: default_paths(default_root())

  @spec default_paths(Path.t()) :: [Path.t()]
  def default_paths(root) when is_binary(root) do
    @default_path_patterns
    |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(root, pattern)) end)
    |> Enum.sort()
    |> Enum.uniq()
  end

  @spec default_exemptions() :: MapSet.t(String.t())
  def default_exemptions, do: load_exemptions(Path.join(default_root(), @default_exemptions_path))

  @spec load_exemptions(Path.t()) :: MapSet.t(String.t())
  def load_exemptions(path) when is_binary(path) do
    if File.exists?(path), do: load_existing_exemptions(path), else: MapSet.new()
  end

  @spec missing_public_specs([Path.t()], keyword()) :: [finding()]
  def missing_public_specs(paths, opts \\ []) when is_list(paths) do
    exemptions =
      opts
      |> Keyword.get(:exemptions, [])
      |> normalize_exemptions()

    paths
    |> Enum.flat_map(&collect_elixir_files/1)
    |> Enum.flat_map(&file_findings(&1, exemptions))
    |> Enum.sort_by(&{&1.file, &1.line, &1.name, &1.arity})
  end

  @spec finding_identifier(finding()) :: String.t()
  def finding_identifier(%{module: module, name: name, arity: arity}) do
    "#{module}.#{name}/#{arity}"
  end

  @spec format_finding(finding()) :: String.t()
  def format_finding(%{} = finding) do
    "#{finding.file}:#{finding.line} missing @spec for #{finding_identifier(finding)}"
  end

  defp default_root, do: Path.expand("../../../..", __DIR__)

  defp load_existing_exemptions(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(MapSet.new(), fn {line, line_number}, exemptions ->
      put_exemption(exemptions, parse_exemption(line, path, line_number))
    end)
  end

  defp put_exemption(exemptions, nil), do: exemptions
  defp put_exemption(exemptions, identifier), do: MapSet.put(exemptions, identifier)

  defp normalize_exemptions(%MapSet{} = exemptions), do: exemptions
  defp normalize_exemptions(exemptions) when is_list(exemptions), do: MapSet.new(exemptions)

  defp collect_elixir_files(path) do
    cond do
      File.regular?(path) and String.ends_with?(path, ".ex") ->
        [path]

      File.dir?(path) ->
        path |> Path.join("**/*.ex") |> Path.wildcard()

      true ->
        []
    end
  end

  defp file_findings(file, exemptions) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true, file: file) do
      ast
      |> module_nodes()
      |> Enum.flat_map(fn {module_name, body} ->
        find_missing_specs(body, module_name, file, exemptions)
      end)
    else
      {:error, {line, error, token}} ->
        raise ArgumentError,
              "unable to parse #{file}:#{line} #{inspect(error)} #{inspect(token)}"

      {:error, reason} ->
        raise ArgumentError, "unable to read #{file}: #{inspect(reason)}"
    end
  end

  defp module_nodes(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_ast, [do: body]]} = node, acc ->
          {node, [{Macro.to_string(module_ast), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp find_missing_specs(body, module_name, file, exemptions) do
    body
    |> normalize_block()
    |> Enum.reduce(initial_state(), fn form, state ->
      consume_form(form, state, module_name, file, exemptions)
    end)
    |> Map.fetch!(:findings)
    |> Enum.reverse()
  end

  defp initial_state do
    %{
      findings: [],
      pending_impl: false,
      pending_specs: MapSet.new(),
      seen_defs: MapSet.new()
    }
  end

  defp consume_form(
         {:@, _meta, [{:spec, _spec_meta, spec_nodes}]},
         state,
         _module,
         _file,
         _exemptions
       ) do
    ids = spec_nodes |> extract_spec_identifiers() |> MapSet.new()
    %{state | pending_specs: MapSet.union(state.pending_specs, ids)}
  end

  defp consume_form(
         {:@, _meta, [{:impl, _impl_meta, _impl_nodes}]},
         state,
         _module,
         _file,
         _exemptions
       ) do
    %{state | pending_impl: true}
  end

  defp consume_form({:@, _meta, _attr}, state, _module, _file, _exemptions), do: state

  defp consume_form({:def, meta, [head_ast | _rest]}, state, module_name, file, exemptions) do
    {name, arity} = def_head_to_identifier(head_ast)
    id = {name, arity}

    if MapSet.member?(state.seen_defs, id) do
      %{state | pending_impl: false, pending_specs: MapSet.new()}
    else
      finding = %{
        file: file,
        module: module_name,
        name: name,
        arity: arity,
        line: Keyword.get(meta, :line, 1)
      }

      next_state = %{
        state
        | pending_impl: false,
          pending_specs: MapSet.new(),
          seen_defs: MapSet.put(state.seen_defs, id)
      }

      if compliant?(finding, state, exemptions) do
        next_state
      else
        %{next_state | findings: [finding | next_state.findings]}
      end
    end
  end

  defp consume_form({:defp, _meta, _args}, state, _module, _file, _exemptions) do
    %{state | pending_impl: false, pending_specs: MapSet.new()}
  end

  defp consume_form(_form, state, _module, _file, _exemptions) do
    %{state | pending_impl: false, pending_specs: MapSet.new()}
  end

  defp compliant?(finding, state, exemptions) do
    MapSet.member?(state.pending_specs, {finding.name, finding.arity}) or
      state.pending_impl or
      MapSet.member?(exemptions, finding_identifier(finding))
  end

  defp normalize_block({:__block__, _meta, forms}), do: forms
  defp normalize_block(form), do: [form]

  defp extract_spec_identifiers(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &extract_spec_identifiers/1)

  defp extract_spec_identifiers({:when, _meta, [inner | _guards]}),
    do: extract_spec_identifiers(inner)

  defp extract_spec_identifiers({:"::", _meta, [head, _return_type]}) do
    case spec_head_to_identifier(head) do
      nil -> []
      id -> [id]
    end
  end

  defp extract_spec_identifiers(_node), do: []

  defp spec_head_to_identifier({:when, _meta, [inner | _guards]}),
    do: spec_head_to_identifier(inner)

  defp spec_head_to_identifier({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp spec_head_to_identifier({name, _meta, nil}) when is_atom(name), do: {name, 0}
  defp spec_head_to_identifier(_head), do: nil

  defp def_head_to_identifier({:when, _meta, [head | _guards]}), do: def_head_to_identifier(head)

  defp def_head_to_identifier({name, _meta, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp def_head_to_identifier({name, _meta, nil}) when is_atom(name), do: {name, 0}

  defp parse_exemption(line, path, line_number) do
    line =
      line
      |> String.split("#", parts: 2)
      |> List.first()
      |> String.trim()

    cond do
      line == "" ->
        nil

      not String.contains?(line, " contract_test:") ->
        raise ArgumentError,
              "#{path}:#{line_number} exemption must include contract_test:path"

      true ->
        [identifier, contract_test] = String.split(line, " contract_test:", parts: 2)
        identifier = String.trim(identifier)
        contract_test = contract_test |> String.trim() |> Path.expand(default_root())
        verify_contract_test!(identifier, contract_test, path, line_number)
        identifier
    end
  end

  defp verify_contract_test!(identifier, contract_test, path, line_number) do
    unless File.exists?(contract_test) do
      raise ArgumentError,
            "#{path}:#{line_number} contract test #{contract_test} does not exist"
    end

    unless contract_test |> File.read!() |> String.contains?(identifier) do
      raise ArgumentError,
            "#{path}:#{line_number} contract test #{contract_test} must mention #{identifier}"
    end
  end
end
