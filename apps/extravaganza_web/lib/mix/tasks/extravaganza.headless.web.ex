defmodule Mix.Tasks.Extravaganza.Headless.Web do
  use Mix.Task

  alias ExtravaganzaWeb.HeadlessServer
  alias ExtravaganzaWeb.HeadlessServer.Runner

  @moduledoc false
  @shortdoc "Start the product headless web shell"

  @switches [
    json: :boolean,
    once: :boolean,
    port: :integer,
    host: :string,
    workflow: :string,
    workflow_path: :string,
    cwd: :string,
    pid_file: :string,
    ready_file: :string,
    env: :keep
  ]

  @impl Mix.Task
  def run(argv) do
    configure_json_logging(argv)

    case parse(argv) do
      {:ok, opts} -> run_opts(opts)
      {:error, reason} -> emit_error(reason, "--json" in argv)
    end
  end

  defp run_opts(opts) do
    case HeadlessServer.plan(opts) do
      {:ok, plan} ->
        if Keyword.get(opts, :once, false) do
          emit_success(plan, Keyword.get(opts, :json, false))
        else
          start_server(plan, opts)
        end

      {:error, reason} ->
        emit_error(reason, Keyword.get(opts, :json, false))
    end
  end

  defp start_server(%{"enabled?" => false}, opts) do
    json? = Keyword.get(opts, :json, false)

    emit_error(:port_required, json?)
  end

  defp start_server(plan, opts) do
    json? = Keyword.get(opts, :json, false)

    case Runner.start(plan, runner_opts(opts)) do
      {:ok, runner} ->
        emit_success(runner.plan, json?)

        with {:ok, receipt} <- Runner.await_shutdown(runner) do
          emit_shutdown(receipt, json?)
        end

      {:error, reason} ->
        emit_error(reason, json?)
    end
  end

  defp runner_opts(opts) do
    opts
    |> Keyword.take([:pid_file, :ready_file])
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp parse(argv) do
    {opts, rest, invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      invalid != [] -> {:error, {:invalid_options, invalid}}
      rest != [] -> {:error, {:unexpected_arguments, rest}}
      true -> {:ok, normalize_opts(opts)}
    end
  end

  defp normalize_opts(opts) do
    opts
    |> Keyword.update(:env, %{}, &parse_env/1)
    |> then(fn opts ->
      if Keyword.has_key?(opts, :env), do: opts, else: Keyword.put(opts, :env, %{})
    end)
  end

  defp parse_env(values) when is_list(values) do
    Map.new(values, fn value ->
      case String.split(value, "=", parts: 2) do
        [key, val] -> {key, val}
        [key] -> {key, ""}
      end
    end)
  end

  defp emit_success(plan, true) do
    IO.puts(
      Jason.encode!(%{
        "ok" => true,
        "schema" => "extravaganza.headless.response.v1",
        "operation" => "web",
        "data" => plan,
        "refs" => %{}
      })
    )

    :ok
  end

  defp emit_success(plan, false) do
    Mix.shell().info("Headless web shell: #{plan["start_command"]}")
    :ok
  end

  defp emit_error(reason, true) do
    IO.puts(
      Jason.encode!(%{
        "ok" => false,
        "schema" => "extravaganza.headless.response.v1",
        "operation" => "web",
        "error" => render_error(reason),
        "refs" => %{}
      })
    )

    :ok
  end

  defp emit_error(reason, false) do
    reason
    |> render_error()
    |> Map.fetch!("message")
    |> Mix.shell().error()

    :ok
  end

  defp emit_shutdown(receipt, true) do
    IO.puts(
      Jason.encode!(%{
        "ok" => true,
        "schema" => "extravaganza.headless.response.v1",
        "operation" => "web.shutdown",
        "data" => receipt,
        "refs" => %{}
      })
    )

    :ok
  end

  defp emit_shutdown(receipt, false) do
    Mix.shell().info("Headless web shell stopped: #{receipt["reason"]}")
    :ok
  end

  defp render_error({:invalid_port, port}) do
    %{
      "code" => "invalid_port",
      "message" => "port must be a non-negative integer",
      "port" => port
    }
  end

  defp render_error({:invalid_host, host}) do
    %{
      "code" => "invalid_host",
      "message" => "host must be a valid IP literal or localhost",
      "host" => host
    }
  end

  defp render_error({:invalid_options, invalid}) do
    %{
      "code" => "invalid_options",
      "message" => "one or more command options are invalid",
      "invalid_options" => inspect(invalid)
    }
  end

  defp render_error({:unexpected_arguments, rest}) do
    %{
      "code" => "unexpected_arguments",
      "message" => "unexpected positional arguments",
      "arguments" => rest
    }
  end

  defp render_error({:server_start_failed, reason}) do
    %{
      "code" => "server_start_failed",
      "message" => inspect(reason)
    }
  end

  defp render_error({:lifecycle_file_failed, path, reason}) do
    %{
      "code" => "lifecycle_file_failed",
      "message" => inspect(reason),
      "path" => path
    }
  end

  defp render_error(:port_required) do
    %{
      "code" => "port_required",
      "message" => "pass --port or configure server.port in the workflow profile"
    }
  end

  defp render_error(reason) do
    %{
      "code" => "web_plan_failed",
      "message" => inspect(reason)
    }
  end

  defp configure_json_logging(argv) do
    if "--json" in argv do
      :logger.set_primary_config(:level, :error)
      Logger.configure(level: :error)
    end
  end
end
