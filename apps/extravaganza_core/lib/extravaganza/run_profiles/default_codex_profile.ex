defmodule Extravaganza.RunProfiles.DefaultCodexProfile do
  @moduledoc """
  Default run profile for Codex-backed coding operations.
  """

  @spec profile() :: map()
  def profile do
    %{
      "runtime" => "session",
      "runtime_driver" => "jido_session",
      "executor" => "codex_cli",
      "model" => "codex-1",
      "approval_mode" => "suggest",
      "output_format" => "json"
    }
  end
end
