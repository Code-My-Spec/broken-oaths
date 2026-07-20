defmodule BrokenOaths.Integrations do
  require Logger

  alias BrokenOaths.Integrations.IntegrationRepository
  alias BrokenOaths.Users.Scope

  @default_providers Application.compile_env(:broken_oaths, :oauth_providers, %{})

  defdelegate get_integration(scope, provider), to: IntegrationRepository
  defdelegate list_integrations(scope), to: IntegrationRepository
  defdelegate update_integration(scope, provider, attrs), to: IntegrationRepository
  defdelegate delete_integration(scope, provider), to: IntegrationRepository
  defdelegate connected?(scope, provider), to: IntegrationRepository

  def list_providers do
    providers() |> Map.keys()
  end

  def authorize_url(provider, opts \\ []) do
    with {:ok, provider_mod} <- fetch_provider(provider) do
      config = provider_mod.config() ++ opts
      strategy = provider_mod.strategy()
      strategy.authorize_url(config)
    end
  end

  @doc """
  Completes the OAuth code exchange for the SOCIAL LOGIN flow — no scope
  yet, because the user may not exist. Returns the normalized provider
  user and token; the caller finds-or-registers the user and then
  persists the integration via `save_integration/4`.
  """
  def handle_login_callback(provider, params, session_params) do
    with {:ok, provider_mod} <- fetch_provider(provider),
         config = provider_mod.config() |> Keyword.put(:session_params, session_params),
         strategy = provider_mod.strategy(),
         {:ok, %{token: token} = result} <- strategy.callback(config, params),
         {:ok, normalized} <- provider_mod.normalize_user(Map.get(result, :user) || %{}) do
      {:ok, %{user: normalized, token: token}}
    end
  end

  @doc "Persists a token obtained by `handle_login_callback/3` under the (now known) user's scope."
  def save_integration(%Scope{} = scope, provider, token, normalized_user) do
    attrs = build_integration_attrs(token, normalized_user)
    IntegrationRepository.upsert_integration(scope, provider, attrs)
  end

  def handle_callback(%Scope{} = scope, provider, params, session_params, opts \\ []) do
    with {:ok, provider_mod} <- fetch_provider(provider),
         config =
           provider_mod.config()
           |> Keyword.put(:session_params, session_params)
           |> Keyword.merge(opts),
         strategy = provider_mod.strategy(),
         {:ok, %{token: token} = result} <- strategy.callback(config, params) do
      user_data = Map.get(result, :user) || %{}

      case provider_mod.normalize_user(user_data) do
        {:ok, normalized} ->
          attrs = build_integration_attrs(token, normalized)
          IntegrationRepository.upsert_integration(scope, provider, attrs)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_provider(provider) do
    case Map.fetch(providers(), provider) do
      {:ok, mod} -> {:ok, mod}
      :error -> {:error, :unsupported_provider}
    end
  end

  defp providers do
    Application.get_env(:broken_oaths, :oauth_providers, @default_providers)
  end

  defp build_integration_attrs(token, normalized_user) do
    %{
      access_token: Map.get(token, "access_token"),
      refresh_token: Map.get(token, "refresh_token"),
      expires_at: calculate_expires_at(token),
      granted_scopes: parse_scopes(Map.get(token, "scope")),
      provider_metadata: Map.new(normalized_user)
    }
  end

  defp calculate_expires_at(%{"expires_in" => expires_in}) when is_integer(expires_in) do
    DateTime.add(DateTime.utc_now(), expires_in, :second)
  end

  defp calculate_expires_at(_token) do
    DateTime.add(DateTime.utc_now(), 365 * 24 * 3600, :second)
  end

  defp parse_scopes(nil), do: []
  defp parse_scopes(scopes) when is_list(scopes), do: scopes

  defp parse_scopes(scopes) when is_binary(scopes) do
    scopes |> String.split(~r/[,\s]+/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end
end
