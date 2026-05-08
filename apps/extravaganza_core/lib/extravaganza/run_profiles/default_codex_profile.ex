defmodule Extravaganza.RunProfiles.DefaultCodexProfile do
  @moduledoc """
  Default run profile for Codex-backed coding operations.
  """

  @profile_key "default_codex"
  @profile_ref "codex_session"
  @profile_kind "temporal_local"
  @revision 1
  @runtime_class "session"
  @lower_runtime_kind "codex_session"
  @capability_id "codex.session.turn"
  @target_ref "codex-default"

  @spec profile_key() :: String.t()
  def profile_key, do: @profile_key

  @spec profile_ref() :: String.t()
  def profile_ref, do: @profile_ref

  @spec profile_kind() :: String.t()
  def profile_kind, do: @profile_kind

  @spec revision() :: pos_integer()
  def revision, do: @revision

  @spec runtime_class() :: String.t()
  def runtime_class, do: @runtime_class

  @spec lower_runtime_kind() :: String.t()
  def lower_runtime_kind, do: @lower_runtime_kind

  @spec capability_id() :: String.t()
  def capability_id, do: @capability_id

  @spec target_ref() :: String.t()
  def target_ref, do: @target_ref

  @spec selection() :: map()
  def selection do
    %{
      "runtime_profile_key" => @profile_key,
      "runtime_profile_ref" => @profile_ref,
      "runtime_profile_kind" => @profile_kind,
      "runtime_profile_revision" => @revision,
      "runtime_class" => @runtime_class,
      "lower_runtime_kind" => @lower_runtime_kind,
      "capability_id" => @capability_id,
      "target_ref" => @target_ref
    }
  end

  @spec profile() :: map()
  def profile do
    Map.merge(selection(), %{
      "runtime" => "session",
      "runtime_driver" => "jido_session",
      "executor" => "codex_cli",
      "model" => "codex-1",
      "approval_mode" => "suggest",
      "output_format" => "json"
    })
  end
end
