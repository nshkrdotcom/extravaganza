defmodule Extravaganza.Topology do
  @moduledoc "Extravaganza virtual server mapping for Chassis profiles."

  @spec virtual_servers_for(String.t(), :dev | :prod, keyword()) :: [atom()]
  def virtual_servers_for("profile:monolith", _env, _opts),
    do: [:vs_app_kit, :vs_mezzanine, :vs_execution_plane]

  def virtual_servers_for("profile:ternary-split-3", _env, _opts),
    do: [:vs_app_kit, :vs_mezzanine, :vs_execution_plane]

  def virtual_servers_for(_profile_ref, _env, _opts), do: [:vs_app_kit]
end
