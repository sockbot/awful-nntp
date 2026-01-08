defmodule AwfulNntp.SA.Client do
  @moduledoc """
  HTTP client for interacting with Something Awful forums.
  Handles authentication and page fetching.
  """

  require Logger

  @sa_base_url "https://forums.somethingawful.com"
  @login_url "#{@sa_base_url}/account.php?action=login"

  @doc """
  Authenticates with SA forums and returns a Req client with cookies.
  """
  def authenticate(username, password) do
    Logger.info("Authenticating with SA forums as #{username}")

    # Create initial client
    client = Req.new(base_url: @sa_base_url)

    # Perform login
    case Req.post(client,
           url: @login_url,
           form: [
             action: "login",
             username: username,
             password: password,
             next: "/"
           ],
           redirect: false
         ) do
      {:ok, response} ->
        # Check if we got authentication cookies
        cookies = get_cookies(response)

        if Map.has_key?(cookies, "bbuserid") or Map.has_key?(cookies, "bbpassword") do
          Logger.info("Successfully authenticated with SA forums")

          # Create authenticated client with cookies
          authenticated_client =
            Req.new(
              base_url: @sa_base_url,
              headers: [
                {"cookie", format_cookies(cookies)},
                {"user-agent", "awful-nntp/0.1.0"}
              ]
            )

          {:ok, authenticated_client}
        else
          Logger.error("Authentication failed - no session cookies received")
          {:error, :auth_failed}
        end

      {:error, reason} ->
        Logger.error("Authentication request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches the forum list page.
  """
  def fetch_forum_list(client) do
    Logger.debug("Fetching forum list")

    case Req.get(client, url: "/") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.error("Unexpected status fetching forum list: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch forum list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches a forum's thread list.
  """
  def fetch_forum(client, forum_id) do
    Logger.debug("Fetching forum #{forum_id}")

    case Req.get(client, url: "/forumdisplay.php", params: [forumid: forum_id]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.error("Unexpected status fetching forum #{forum_id}: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch forum #{forum_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches a thread's posts.
  """
  def fetch_thread(client, thread_id) do
    Logger.debug("Fetching thread #{thread_id}")

    case Req.get(client, url: "/showthread.php", params: [threadid: thread_id]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.error("Unexpected status fetching thread #{thread_id}: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch thread #{thread_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper functions

  defp get_cookies(response) do
    response
    |> Map.get(:headers, %{})
    |> Enum.filter(fn {name, _value} -> String.downcase(to_string(name)) == "set-cookie" end)
    |> Enum.flat_map(fn {_name, value} ->
      # value can be a string or list of strings
      value = if is_list(value), do: value, else: [value]
      Enum.map(value, &parse_cookie/1)
    end)
    |> Enum.reject(fn {k, _v} -> is_nil(k) end)
    |> Enum.into(%{})
  end

  defp parse_cookie(cookie_string) when is_binary(cookie_string) do
    cookie_string
    |> String.split(";")
    |> List.first()
    |> String.split("=", parts: 2)
    |> case do
      [name, value] -> {String.trim(name), String.trim(value)}
      _ -> {nil, nil}
    end
  end

  defp parse_cookie(_), do: {nil, nil}

  defp format_cookies(cookies) do
    cookies
    |> Enum.reject(fn {k, _v} -> is_nil(k) end)
    |> Enum.map_join("; ", fn {k, v} -> "#{k}=#{v}" end)
  end
end
