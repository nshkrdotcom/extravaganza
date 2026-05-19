defmodule ExtravaganzaWeb.HeadlessSurfaceOptions do
  @moduledoc """
  Request-local backend context for the headless web and API surfaces.

  The web shell defaults to the deterministic product fixture lane. Tests and
  caller-owned plugs can override those backends by placing options in
  `conn.private`; controllers then pass the resolved options explicitly to the
  product surface.
  """

  import Plug.Conn, only: [put_private: 3]

  alias Extravaganza.HeadlessFixtureBackend

  @private_key :extravaganza_headless_surface_opts

  @spec private_key() :: atom()
  def private_key, do: @private_key

  @spec default() :: keyword()
  def default do
    [
      headless_fixture_context?: true,
      skip_bootstrap?: true,
      headless_backend: HeadlessFixtureBackend,
      runtime_backend: HeadlessFixtureBackend,
      source_backend: HeadlessFixtureBackend
    ]
  end

  @spec for_conn(Plug.Conn.t()) :: keyword()
  def for_conn(conn) do
    Keyword.merge(default(), Map.get(conn.private, @private_key, []))
  end

  @spec put(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def put(conn, overrides) when is_list(overrides) do
    put_private(conn, @private_key, Keyword.merge(default(), overrides))
  end
end
