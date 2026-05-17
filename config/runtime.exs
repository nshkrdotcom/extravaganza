import Config

runtime_stack = Mezzanine.Execution.RuntimeStack
runtime_repos = Enum.uniq(runtime_stack.repo_modules() ++ [Mezzanine.Archival.Repo])
runtime_domains = Enum.uniq(runtime_stack.ash_domains() ++ [Mezzanine.Archival])

config :ash, domains: runtime_domains

config :extravaganza_core,
  ecto_repos: runtime_repos

config :mezzanine_ops_domain,
  ecto_repos: [runtime_stack.ops_domain_repo()],
  ash_domains: runtime_stack.ops_domain_ash_domains()

config :app_kit_mezzanine_bridge,
  ecto_repos: runtime_repos

github_access_token = System.get_env("GH_TOKEN") || System.get_env("GITHUB_TOKEN")

if is_binary(github_access_token) and String.trim(github_access_token) != "" do
  config :mezzanine_integration_bridge,
         Mezzanine.IntegrationBridge.ProviderAdapters.GitHub.PrEvidenceRuntime,
         access_token: String.trim(github_access_token)

  config :mezzanine_integration_bridge,
         Mezzanine.IntegrationBridge.ProviderAdapters.GitHub.PrBranchCleanupRuntime,
         access_token: String.trim(github_access_token)
end

config :jido_integration_v2_github, Jido.Integration.V2.Connectors.GitHub.ClientFactory,
  transport: Pristine.Adapters.Transport.Finch

case config_env() do
  :dev ->
    config :mezzanine_ops_domain, runtime_stack.ops_domain_repo(),
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: "mezzanine_ops_domain_dev",
      show_sensitive_data_on_connection_error: true,
      pool_size: 10

  :test ->
    config :mezzanine_ops_domain, runtime_stack.ops_domain_repo(),
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      database: "mezzanine_ops_domain_test",
      pool: Ecto.Adapters.SQL.Sandbox,
      pool_size: 10,
      show_sensitive_data_on_connection_error: true

  _other ->
    :ok
end

if System.get_env("PHX_SERVER") do
  config :extravaganza_web, ExtravaganzaWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :extravaganza_web, ExtravaganzaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
