defmodule BrokenOaths.Secrets do
  @moduledoc """
  Boot-time secret loader. Pulls every parameter under
  `/broken_oaths/<APP_ENV>/` from AWS SSM Parameter Store and writes it
  into the OS environment so the rest of `config/runtime.exs` (which
  reads `System.get_env/1`) sees the values as if they were set in the
  container's launch env.

  Invoked from the top of `config/runtime.exs` in `:prod` when
  `APP_ENV` is set (UAT and prod boxes — both compile with
  `MIX_ENV=prod`). Local dev/test never call this.

  Kamal carries only AWS bootstrap credentials
  (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for the per-env IAM user
  `broken-oaths-<env>-app`) — app secrets never flow through the
  operator's shell or Kamal. See the devops repo's `infra.md`.

  The IAM principal needs `ssm:GetParametersByPath` on
  `arn:aws:ssm:us-east-1:889081505590:parameter/broken_oaths/<env>/*`
  and `kms:Decrypt` on the default `aws/ssm` key.
  """

  @path_prefix "/broken_oaths/"

  # The typical failure is a transient network blip during a box-wide
  # restart, not SSM throttling — fixed backoff, few attempts.
  @max_attempts 3
  @backoff_ms 1000

  @doc """
  Load all parameters for `app_env` ("prod" | "uat") into System env.
  Raises on missing IAM creds, an empty parameter path, or any SSM
  error after #{@max_attempts} attempts.
  """
  @spec load!(String.t()) :: :ok
  def load!(app_env) when app_env in ["prod", "uat"] do
    # These ship with the release as regular deps, but nothing has
    # started them yet when runtime.exs runs. Req (not hackney) is the
    # HTTP client — hackney isn't in this app's tree.
    {:ok, _} = Application.ensure_all_started(:ex_aws)
    {:ok, _} = Application.ensure_all_started(:req)
    Application.put_env(:ex_aws, :http_client, BrokenOaths.Secrets.ReqClient)

    path = @path_prefix <> app_env <> "/"
    parameters = fetch_all(path, nil, [])

    if parameters == [] do
      raise """
      No SSM parameters found under #{path}.
      Verify AWS credentials and that the path has parameters.
      """
    end

    Enum.each(parameters, fn %{"Name" => name, "Value" => value} ->
      key = String.replace_prefix(name, path, "")
      System.put_env(key, value)
    end)

    :ok
  end

  def load!(other),
    do: raise(ArgumentError, "BrokenOaths.Secrets.load!/1: unsupported APP_ENV #{inspect(other)}")

  defp fetch_all(path, next_token, acc) do
    case fetch_page(path, next_token) do
      {:ok, %{"Parameters" => params, "NextToken" => token}} when is_binary(token) ->
        fetch_all(path, token, [params | acc])

      {:ok, %{"Parameters" => params}} ->
        Enum.reverse([params | acc]) |> List.flatten()
    end
  end

  defp fetch_page(path, next_token, attempt \\ 1) do
    opts = [recursive: true, with_decryption: true]
    opts = if next_token, do: Keyword.put(opts, :next_token, next_token), else: opts

    case ExAws.SSM.get_parameters_by_path(path, opts) |> ExAws.request() do
      {:ok, page} ->
        {:ok, page}

      {:error, _reason} when attempt < @max_attempts ->
        # `reason` can carry AWS auth diagnostics — log only bounded fields.
        :logger.warning(
          "BrokenOaths.Secrets: SSM fetch failed for #{path} (attempt #{attempt}/#{@max_attempts}); retrying in #{@backoff_ms}ms"
        )

        Process.sleep(@backoff_ms)
        fetch_page(path, next_token, attempt + 1)

      {:error, reason} ->
        raise """
        BrokenOaths.Secrets.load!/1: SSM fetch failed for #{path} after \
        #{@max_attempts} attempts: #{inspect(reason)}
        """
    end
  end
end
