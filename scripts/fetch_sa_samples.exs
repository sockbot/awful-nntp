#!/usr/bin/env elixir

# Script to test SA authentication and fetch sample pages
# Usage: mix run scripts/fetch_sa_samples.exs

# Load environment variables
File.cd!(__DIR__ <> "/..")
Code.eval_file("config/dotenv.exs")

defmodule SAFetcher do
  require Logger

  def run do
    username = System.get_env("SA_USERNAME")
    password = System.get_env("SA_PASSWORD")

    if is_nil(username) or username == "" do
      IO.puts("Error: SA_USERNAME not set in .env file")
      System.halt(1)
    end

    if is_nil(password) or password == "" do
      IO.puts("Error: SA_PASSWORD not set in .env file")
      System.halt(1)
    end

    IO.puts("Authenticating as #{username}...")
    
    case AwfulNntp.SA.Client.authenticate(username, password) do
      {:ok, client} ->
        IO.puts("✓ Authentication successful!")
        fetch_samples(client)

      {:error, reason} ->
        IO.puts("✗ Authentication failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp fetch_samples(client) do
    # Create samples directory
    File.mkdir_p!("samples")

    # Fetch forum list
    IO.puts("\nFetching forum list...")

    case AwfulNntp.SA.Client.fetch_forum_list(client) do
      {:ok, html} ->
        File.write!("samples/forum_list.html", html)
        IO.puts("✓ Saved to samples/forum_list.html (#{byte_size(html)} bytes)")

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}")
    end

    # Fetch a sample forum (General Bullshit = forumid 1)
    IO.puts("\nFetching forum threads (General Bullshit)...")

    case AwfulNntp.SA.Client.fetch_forum(client, "1") do
      {:ok, html} ->
        File.write!("samples/forum_threads.html", html)
        IO.puts("✓ Saved to samples/forum_threads.html (#{byte_size(html)} bytes)")

      {:error, reason} ->
        IO.puts("✗ Failed: #{inspect(reason)}")
    end

    # Fetch a sample thread (you'll need to pick a thread ID from the forum page)
    # For now, we'll skip this until we parse the forum page
    IO.puts("\nNote: Thread fetching will be added after parsing forum page")
    IO.puts("\nDone! Check the samples/ directory for HTML files.")
  end
end

SAFetcher.run()
