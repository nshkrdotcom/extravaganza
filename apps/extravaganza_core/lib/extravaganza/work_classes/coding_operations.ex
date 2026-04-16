defmodule Extravaganza.WorkClasses.CodingOperations do
  @moduledoc """
  Product work-class definition for Linear-originated coding tasks.
  """

  alias Extravaganza.PolicyPresets
  alias Extravaganza.RunProfiles.DefaultCodexProfile

  @spec definition() :: map()
  def definition do
    %{
      name: "coding_operations",
      kind: "coding_task",
      intake_schema: %{
        "required" => ["external_ref", "title"],
        "optional" => ["description", "state", "team", "labels", "identifier", "url"]
      },
      default_review_profile: PolicyPresets.default_review_gates(),
      default_run_profile: DefaultCodexProfile.profile()
    }
  end
end
