defmodule Extravaganza.PlacementProfiles.LocalDefault do
  @moduledoc """
  Default single-node placement profile for the proving deployment.
  """

  @spec profile() :: map()
  def profile do
    %{
      profile_id: "local_default",
      strategy: "affinity",
      target_selector: %{"runtime_driver" => "jido_session"},
      runtime_preferences: %{"locality" => "same_region", "topology" => "single_node"},
      workspace_policy: %{"root_mode" => "per_work", "sandbox_profile" => "strict"},
      metadata: %{"preset" => "local_default"}
    }
  end
end
