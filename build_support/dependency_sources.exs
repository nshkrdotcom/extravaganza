defmodule DependencySources do
  @moduledoc false

  @helper_version 2
  @source_keys [:path, :github, :hex]
  @source_by_name Map.new(@source_keys, &{Atom.to_string(&1), &1})
  @github_option_keys [:branch, :ref, :tag, :subdir]
  @github_option_by_name Map.new(@github_option_keys, &{Atom.to_string(&1), &1})

  def helper_version, do: @helper_version

  def config!(repo_root \\ Path.dirname(__DIR__)) do
    repo_root
    |> Path.expand()
    |> Path.join("build_support/dependency_sources.config.exs")
    |> load_config!()
  end

  def deps(repo_root \\ Path.dirname(__DIR__), opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = config!(repo_root)
    app_lookup = app_lookup(config)
    overrides = load_local_overrides(repo_root)
    publish? = Keyword.get(opts, :publish?, publish_mode?())

    config
    |> deps_config()
    |> Enum.map(fn {app, dep_config} ->
      app = normalize_app!(app, app_lookup)
      dep_config = normalize_dep_config!(dep_config)
      override = local_override(app, overrides)
      source = selected_source!(app, dep_config, override, publish?, repo_root)
      dep_tuple(app, dep_config, source, repo_root, override, [])
    end)
  end

  def dep(app, repo_root \\ Path.dirname(__DIR__), extra_opts \\ []) do
    repo_root = Path.expand(repo_root)
    config = config!(repo_root)
    app_lookup = app_lookup(config)
    overrides = load_local_overrides(repo_root)
    app = normalize_app!(app, app_lookup)
    dep_config = dep_config_for!(app, config, app_lookup)
    override = local_override(app, overrides)
    source = selected_source!(app, dep_config, override, publish_mode?(), repo_root)

    dep_tuple(app, dep_config, source, repo_root, override, extra_opts)
  end

  defp load_config!(path) do
    config =
      path
      |> File.read!()
      |> Code.string_to_quoted!(file: path)
      |> config_term!(Path.dirname(path))

    unless is_map(config) or Keyword.keyword?(config) do
      raise ArgumentError, "dependency source config must be a literal map or keyword list"
    end

    config
  end

  defp load_local_overrides(repo_root) do
    path = Path.join(repo_root, ".dependency_sources.local.exs")

    if File.regular?(path) do
      overrides =
        path
        |> File.read!()
        |> Code.string_to_quoted!(file: path)
        |> literal_term!()

      Map.new(overrides[:deps] || overrides["deps"] || %{})
    else
      %{}
    end
  end

  defp deps_config(config) do
    deps = config[:deps] || config["deps"] || config
    Map.new(deps)
  end

  defp dep_config_for!(app, config, app_lookup) do
    deps =
      config
      |> deps_config()
      |> Map.new(fn {configured_app, dep_config} ->
        {normalize_app!(configured_app, app_lookup), normalize_dep_config!(dep_config)}
      end)

    case Map.fetch(deps, app) do
      {:ok, dep_config} -> dep_config
      :error -> raise ArgumentError, "dependency source config is missing #{app}"
    end
  end

  defp app_lookup(config) do
    config
    |> deps_config()
    |> Map.keys()
    |> Map.new(fn
      app when is_atom(app) -> {Atom.to_string(app), app}
      app when is_binary(app) -> {app, app}
    end)
  end

  defp normalize_app!(app, _app_lookup) when is_atom(app), do: app

  defp normalize_app!(app, app_lookup) when is_binary(app) do
    case Map.fetch(app_lookup, app) do
      {:ok, normalized} ->
        normalized

      :error ->
        raise ArgumentError, "dependency source config is missing #{app}"
    end
  end

  defp normalize_dep_config!(config) when is_map(config), do: config
  defp normalize_dep_config!(config) when is_list(config), do: Map.new(config)

  defp local_override(app, overrides),
    do: normalize_dep_config!(overrides[app] || overrides[Atom.to_string(app)] || %{})

  defp selected_source!(app, config, override, publish?, repo_root) do
    override_source = override[:source] || override["source"]

    cond do
      override_source ->
        normalize_source!(override_source)

      publish? ->
        source_from_order!(
          app,
          config,
          config[:publish_order] || config["publish_order"] || [:hex],
          repo_root
        )

      true ->
        source_from_order!(
          app,
          config,
          config[:default_order] || config["default_order"] || [:path, :github, :hex],
          repo_root
        )
    end
  end

  defp source_from_order!(app, config, order, repo_root) do
    order
    |> Enum.map(&normalize_source!/1)
    |> Enum.find(fn
      :path -> configured_path_available?(config, repo_root)
      source -> configured?(config, source)
    end)
    |> case do
      nil -> raise ArgumentError, "no dependency source is available for #{app}"
      source -> source
    end
  end

  defp configured_path_available?(config, repo_root) do
    case config[:path] || config["path"] do
      nil ->
        false

      path when is_binary(path) ->
        usable_sibling_path?(path, repo_root)

      paths when is_list(paths) ->
        Enum.any?(paths, &usable_sibling_path?(&1, repo_root))

      _other ->
        false
    end
  end

  # A configured `:path` candidate only counts as a usable sibling
  # checkout when (1) it exists on disk and (2) it does not resolve to a
  # Mix-managed `deps/` directory.
  #
  # Without (2), running `mix deps.get` from a fresh clone could
  # materialize multiple sibling deps under the parent project's
  # `deps/`, and this helper -- invoked from within one of those
  # child deps with `repo_root = <parent>/deps/<child>` -- would then
  # mistake another Mix-fetched dep for a developer sibling checkout
  # and pick `:path`. That produces a divergent source vs. however a
  # peer dep already declared the same app, and Mix refuses to
  # resolve with the "overriding a child dependency" error.
  defp usable_sibling_path?(path, repo_root) do
    abs = Path.expand(path, repo_root)
    File.exists?(abs) and not under_mix_deps_dir?(repo_root, abs)
  end

  # When `repo_root` itself sits under a path component named `deps`,
  # `mix_deps_ancestor/1` returns the absolute path to that ancestor
  # (the parent project's `deps/` directory). A candidate that resolves
  # to anything under that same ancestor is therefore another
  # Mix-fetched sibling, not a developer workspace checkout.
  defp under_mix_deps_dir?(repo_root, abs) do
    case mix_deps_ancestor(repo_root) do
      nil -> false
      deps_dir -> String.starts_with?(abs <> "/", deps_dir <> "/")
    end
  end

  defp mix_deps_ancestor(repo_root) do
    segments = repo_root |> Path.expand() |> Path.split()

    segments
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.find(fn {seg, _idx} -> seg == "deps" end)
    |> case do
      nil ->
        nil

      {"deps", reverse_index} ->
        forward_index = length(segments) - reverse_index
        segments |> Enum.take(forward_index) |> Path.join()
    end
  end

  defp configured?(config, source),
    do: not is_nil(config[source] || config[Atom.to_string(source)])

  defp dep_tuple(app, config, :path, repo_root, override, extra_opts) do
    path = override[:path] || override["path"] || config[:path] || config["path"]

    path =
      if is_list(path), do: Enum.find(path, &File.exists?(Path.expand(&1, repo_root))), else: path

    {app, Keyword.merge([path: Path.expand(path, repo_root)], dep_options(config, extra_opts))}
  end

  defp dep_tuple(app, config, :github, _repo_root, override, extra_opts) do
    github = Map.new(config[:github] || config["github"] || %{})
    github = Map.merge(github, Map.drop(override, [:source, "source"]))
    repo = github[:repo] || github["repo"]

    opts =
      github
      |> Enum.flat_map(fn
        {key, _value} when key in [:repo, "repo"] ->
          []

        {key, value} ->
          option_key = normalize_option_key(key)

          if option_key in @github_option_keys do
            [{option_key, value}]
          else
            []
          end
      end)

    {app, Keyword.merge([github: repo], Keyword.merge(opts, dep_options(config, extra_opts)))}
  end

  defp dep_tuple(app, config, :hex, _repo_root, override, extra_opts) do
    requirement = override[:hex] || override["hex"] || config[:hex] || config["hex"]

    case dep_options(config, extra_opts) do
      [] -> {app, requirement}
      opts -> {app, requirement, opts}
    end
  end

  defp dep_options(config, extra_opts) do
    config
    |> Map.get(:opts, config["opts"] || config[:options] || config["options"] || [])
    |> keyword_options()
    |> Keyword.merge(keyword_options(extra_opts))
  end

  defp keyword_options(opts) when is_list(opts), do: opts
  defp keyword_options(opts) when is_map(opts), do: Map.to_list(opts)
  defp keyword_options(_opts), do: []

  defp normalize_source!(source) when source in @source_keys, do: source

  defp normalize_source!(source) when is_binary(source) do
    case Map.fetch(@source_by_name, source) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "unknown dependency source #{inspect(source)}"
    end
  end

  defp normalize_option_key(key) when is_atom(key), do: key

  defp normalize_option_key(key) when is_binary(key) do
    case Map.fetch(@github_option_by_name, key) do
      {:ok, normalized} -> normalized
      :error -> key
    end
  end

  defp config_term!(quoted, config_dir) do
    eval_config_ast!(quoted, %{__DIR__: config_dir})
  end

  defp eval_config_ast!({:__block__, _meta, expressions}, env) do
    {value, _env} =
      Enum.reduce(expressions, {nil, env}, fn expression, {_previous, env} ->
        eval_config_expression!(expression, env)
      end)

    value
  end

  defp eval_config_ast!({:%{}, _meta, pairs}, env) do
    Map.new(pairs, fn {key, value} ->
      {eval_config_ast!(key, env), eval_config_ast!(value, env)}
    end)
  end

  defp eval_config_ast!(values, env) when is_list(values),
    do: Enum.map(values, &eval_config_ast!(&1, env))

  defp eval_config_ast!({:<<>>, _meta, parts}, env) do
    parts
    |> Enum.map(&eval_binary_part!(&1, env))
    |> IO.iodata_to_binary()
  end

  defp eval_config_ast!({:"::", _meta, [expression, {:binary, _binary_meta, nil}]}, env),
    do: eval_config_ast!(expression, env)

  defp eval_config_ast!(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Path]}, :expand]}, _call_meta, args},
         env
       )
       when length(args) in [1, 2] do
    args = Enum.map(args, &eval_config_ast!(&1, env))
    apply(Path, :expand, args)
  end

  defp eval_config_ast!(
         {{:., _meta, [{:__aliases__, _alias_meta, [:Path]}, :join]}, _call_meta, args},
         env
       )
       when length(args) in [1, 2] do
    args = Enum.map(args, &eval_config_ast!(&1, env))
    apply(Path, :join, args)
  end

  defp eval_config_ast!({{:., _meta, [Kernel, :to_string]}, _call_meta, [value]}, env),
    do: to_string(eval_config_ast!(value, env))

  defp eval_config_ast!({{:., _meta, [{name, _name_meta, nil}]}, _call_meta, args}, env)
       when is_atom(name) do
    name
    |> fetch_config_env!(env)
    |> call_config_function!(Enum.map(args, &eval_config_ast!(&1, env)))
  end

  defp eval_config_ast!({:fn, _meta, [{:->, _arrow_meta, [params, body]}]}, env) do
    param_names =
      Enum.map(params, fn
        {name, _param_meta, nil} when is_atom(name) ->
          name

        other ->
          raise ArgumentError,
                "dependency source config contains unsupported function parameter #{inspect(other)}"
      end)

    {:dependency_source_config_function, param_names, body, env}
  end

  defp eval_config_ast!({name, _meta, nil}, env) when is_atom(name),
    do: fetch_config_env!(name, env)

  defp eval_config_ast!({left, right}, env),
    do: {eval_config_ast!(left, env), eval_config_ast!(right, env)}

  defp eval_config_ast!(value, _env)
       when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value) or
              is_boolean(value) or is_nil(value),
       do: value

  defp eval_config_ast!(other, _env) do
    raise ArgumentError,
          "dependency source config contains unsupported expression #{inspect(other)}"
  end

  defp eval_config_expression!({:=, _meta, [{name, _name_meta, nil}, value]}, env)
       when is_atom(name) do
    value = eval_config_ast!(value, env)
    {value, Map.put(env, name, value)}
  end

  defp eval_config_expression!(expression, env), do: {eval_config_ast!(expression, env), env}

  defp eval_binary_part!({:"::", _meta, [expression, {:binary, _binary_meta, nil}]}, env),
    do: eval_config_ast!(expression, env)

  defp eval_binary_part!(part, env), do: eval_config_ast!(part, env)

  defp fetch_config_env!(name, env) do
    case Map.fetch(env, name) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, "dependency source config references unknown binding #{name}"
    end
  end

  defp call_config_function!(
         {:dependency_source_config_function, param_names, body, captured_env},
         args
       ) do
    if length(param_names) != length(args) do
      raise ArgumentError, "dependency source config calls function with wrong arity"
    end

    function_env =
      param_names
      |> Enum.zip(args)
      |> Map.new()
      |> Map.merge(captured_env, fn _key, arg_value, _captured_value -> arg_value end)

    eval_config_ast!(body, function_env)
  end

  defp call_config_function!(other, _args) do
    raise ArgumentError,
          "dependency source config attempts to call non-config function #{inspect(other)}"
  end

  defp literal_term!(value)
       when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value) or
              is_boolean(value) or is_nil(value),
       do: value

  defp literal_term!({:%{}, _meta, pairs}) do
    Map.new(pairs, fn {key, value} -> {literal_term!(key), literal_term!(value)} end)
  end

  defp literal_term!(values) when is_list(values), do: Enum.map(values, &literal_term!/1)

  defp literal_term!({left, right}), do: {literal_term!(left), literal_term!(right)}

  defp literal_term!(other) do
    raise ArgumentError,
          "dependency source config contains non-literal expression #{inspect(other)}"
  end

  defp publish_mode? do
    System.argv()
    |> Enum.join(" ")
    |> String.contains?("hex.")
  end
end
