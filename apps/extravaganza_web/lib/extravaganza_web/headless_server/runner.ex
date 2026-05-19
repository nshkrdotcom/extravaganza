defmodule ExtravaganzaWeb.HeadlessServer.Runner do
  @moduledoc false

  alias ExtravaganzaWeb.{Endpoint, HeadlessServer}

  @signals [:sigterm, :sighup]

  defstruct [:plan, :server_pid, :endpoint_pid, :pid_file, :ready_file]

  @type shutdown_reason :: atom() | {:endpoint_down, term()}
  @type t :: %__MODULE__{
          plan: map(),
          server_pid: pid() | nil,
          endpoint_pid: pid() | nil,
          pid_file: String.t() | nil,
          ready_file: String.t() | nil
        }

  @spec start(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(plan, opts \\ []) do
    case HeadlessServer.start_link(plan) do
      {:ok, server_pid} ->
        runner = %__MODULE__{
          plan: Map.put(plan, "bound_port", HeadlessServer.bound_port()),
          server_pid: server_pid,
          endpoint_pid: Process.whereis(Endpoint),
          pid_file: Keyword.get(opts, :pid_file),
          ready_file: Keyword.get(opts, :ready_file)
        }

        with :ok <- write_lifecycle_files(runner) do
          {:ok, runner}
        end

      :ignore ->
        {:error, :port_required}

      {:error, reason} ->
        {:error, {:server_start_failed, reason}}
    end
  end

  @spec await_shutdown(t(), keyword()) :: {:ok, map()}
  def await_shutdown(%__MODULE__{} = runner, opts \\ []) do
    shutdown = wait_for_shutdown(Keyword.put_new(opts, :endpoint_pid, runner.endpoint_pid))
    stop_server(runner)

    {:ok, shutdown_receipt(runner, shutdown)}
  end

  @spec wait_for_shutdown(keyword()) :: %{source: String.t(), reason: shutdown_reason()}
  def wait_for_shutdown(opts \\ []) do
    target = self()
    trap? = Keyword.get(opts, :signal_traps?, true)
    signal_refs = if trap?, do: install_signal_traps(target), else: []
    monitor_ref = monitor_endpoint(Keyword.get(opts, :endpoint_pid))
    timeout = Keyword.get(opts, :timeout, :infinity)

    try do
      wait_loop(monitor_ref, timeout)
    after
      untrap_signals(signal_refs)
      demonitor_endpoint(monitor_ref)
    end
  end

  @spec shutdown_receipt(t(), map()) :: map()
  def shutdown_receipt(%__MODULE__{} = runner, %{source: source, reason: reason}) do
    %{
      "status" => "stopped",
      "source" => source,
      "reason" => render_reason(reason),
      "bound_port" => Map.get(runner.plan, "bound_port"),
      "endpoint_stopped?" => HeadlessServer.bound_port() == nil,
      "pid_file" => runner.pid_file,
      "ready_file" => runner.ready_file
    }
    |> compact()
  end

  defp wait_loop(monitor_ref, timeout) do
    receive do
      :shutdown ->
        %{source: "message", reason: :shutdown}

      {:shutdown, reason} ->
        %{source: "message", reason: reason}

      {:headless_server_shutdown, signal} ->
        %{source: "signal", reason: signal}

      {:DOWN, ^monitor_ref, :process, _pid, reason} when is_reference(monitor_ref) ->
        %{source: "endpoint_monitor", reason: {:endpoint_down, reason}}
    after
      timeout ->
        %{source: "timeout", reason: :timeout}
    end
  end

  defp install_signal_traps(target) do
    Enum.flat_map(@signals, &install_signal_trap(&1, target))
  end

  defp install_signal_trap(signal, target) do
    case System.trap_signal(signal, signal_trap(target, signal)) do
      {:ok, id} -> [{signal, id}]
      {:error, _reason} -> []
    end
  end

  defp signal_trap(target, signal) do
    fn ->
      send(target, {:headless_server_shutdown, signal})
      :ok
    end
  end

  defp untrap_signals(signal_refs) do
    Enum.each(signal_refs, fn {signal, id} -> System.untrap_signal(signal, id) end)
  end

  defp monitor_endpoint(pid) when is_pid(pid), do: Process.monitor(pid)
  defp monitor_endpoint(_pid), do: nil

  defp demonitor_endpoint(nil), do: :ok
  defp demonitor_endpoint(ref), do: Process.demonitor(ref, [:flush])

  defp stop_server(%__MODULE__{server_pid: pid}) when is_pid(pid),
    do: Supervisor.stop(pid, :normal, 5_000)

  defp stop_server(_runner), do: :ok

  @spec write_lifecycle_files(t()) :: :ok | {:error, term()}
  def write_lifecycle_files(%__MODULE__{} = runner) do
    case write_pid_file(runner) do
      :ok -> write_ready_file(runner)
      {:error, _reason} = error -> error
    end
  end

  defp write_pid_file(%__MODULE__{pid_file: nil}), do: :ok

  defp write_pid_file(%__MODULE__{pid_file: path}) do
    write_file(path, "#{System.pid()}\n")
  end

  defp write_ready_file(%__MODULE__{ready_file: nil}), do: :ok

  defp write_ready_file(%__MODULE__{ready_file: path, plan: plan}) do
    write_file(
      path,
      Jason.encode!(%{
        "status" => "ready",
        "bound_port" => Map.get(plan, "bound_port"),
        "operation" => "web"
      }) <> "\n"
    )
  end

  defp write_file(path, content) when is_binary(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
    |> case do
      :ok -> File.write(path, content)
      {:error, reason} -> {:error, {:lifecycle_file_failed, path, reason}}
    end
  end

  defp render_reason({:endpoint_down, reason}), do: "endpoint_down: #{inspect(reason)}"
  defp render_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp render_reason(reason), do: inspect(reason)

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end
end
