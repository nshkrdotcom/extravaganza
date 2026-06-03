defmodule Extravaganza.Topology do
  @moduledoc "Extravaganza virtual server mapping for Chassis profiles."

  alias Chassis.Stack.ProfileResolver

  @spec virtual_servers_for(:extravaganza | :stack_coder, String.t(), atom()) ::
          {:ok, [atom()]} | {:error, term()}
  def virtual_servers_for(app_atom, profile_ref, node_atom)
      when app_atom in [:extravaganza, :stack_coder] and is_binary(profile_ref) and
             is_atom(node_atom) do
    with {:ok, resolved} <- ProfileResolver.resolve(profile_ref, current_env()) do
      node_str = Atom.to_string(node_atom)

      virtual_servers =
        resolved.placements
        |> Enum.filter(&node_matches?(&1.node_name_pattern, node_str))
        |> Enum.flat_map(& &1.virtual_servers)
        |> filter_for_app(app_atom)
        |> Enum.uniq()

      {:ok, virtual_servers}
    end
  end

  defp node_matches?("monolith@*", _node_str), do: true

  defp node_matches?(pattern, node_str) do
    prefix = String.replace_suffix(pattern, "@*", "@")
    String.starts_with?(node_str, prefix)
  end

  defp filter_for_app(vs_list, :extravaganza), do: vs_list
  defp filter_for_app(vs_list, :stack_coder), do: vs_list

  defp current_env do
    case Application.get_env(:extravaganza_core, :chassis_env, :dev) do
      :prod -> :prod
      "prod" -> :prod
      _ -> :dev
    end
  end
end
