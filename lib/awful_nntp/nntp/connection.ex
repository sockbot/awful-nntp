defmodule AwfulNntp.NNTP.Connection do
  @moduledoc """
  GenServer that handles a single NNTP client connection.
  Processes commands and sends responses.
  """

  use GenServer
  require Logger

  alias AwfulNntp.NNTP.Protocol

  defstruct [:socket, :current_group, :authenticated, :username, :sa_client, :forum_cache]

  @doc """
  Starts a connection handler for the given socket.
  """
  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    state = %__MODULE__{
      socket: socket,
      current_group: nil,
      authenticated: false,
      username: nil,
      sa_client: nil,
      forum_cache: %{}
    }

    # Send welcome banner
    send_response(socket, 200, "awful-nntp ready (posting ok)")
    
    # Activate socket to receive messages
    :inet.setopts(socket, active: true)

    {:ok, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    case Protocol.parse_command(data) do
      {:ok, command, args} ->
        # Redact password from logs
        safe_args = if command == :authinfo and length(args) == 2 and hd(args) == "PASS" do
          ["PASS", "[REDACTED]"]
        else
          args
        end
        Logger.info("Command: #{command} #{inspect(safe_args)}")
        new_state = handle_command(command, args, state)
        {:noreply, new_state}

      {:error, :empty_command} ->
        {:noreply, state}

      {:error, :unknown_command} ->
        Logger.warning("Unknown command received: #{String.trim(data)}")
        send_response(socket, 500, "Unknown command")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Client disconnected")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.error("TCP error: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  # Command handlers

  defp handle_command(:capabilities, _args, state) do
    capabilities = [
      "VERSION 2",
      "READER",
      "LIST ACTIVE OVERVIEW.FMT",
      "OVER",
      "AUTHINFO USER"
    ]

    send_multi_line_response(state.socket, 101, "Capability list", capabilities)
    state
  end

  defp handle_command(:quit, _args, state) do
    send_response(state.socket, 205, "Closing connection")
    :gen_tcp.close(state.socket)
    state
  end

  defp handle_command(:list, [], state) do
    # Fetch forums from SA (public, no auth needed for list)
    case fetch_forum_list() do
      {:ok, forums} ->
        # Convert to NNTP newsgroup format
        lines =
          forums
          |> Enum.map(fn forum ->
            newsgroup = AwfulNntp.Mapping.forum_to_newsgroup(forum.name)
            # Format: newsgroup high low status
            # For now, use 0 1 y (posting allowed)
            "#{newsgroup} 0 1 y"
          end)

        send_multi_line_response(state.socket, 215, "Newsgroups follow", lines)

      {:error, _reason} ->
        # Fall back to empty list on error
        send_multi_line_response(state.socket, 215, "Newsgroups follow", [])
    end

    state
  end

  defp handle_command(:list, ["OVERVIEW.FMT"], state) do
    overview_format = [
      "Subject:",
      "From:",
      "Date:",
      "Message-ID:",
      "References:",
      ":bytes",
      ":lines"
    ]

    send_multi_line_response(state.socket, 215, "Overview format follows", overview_format)
    state
  end

  defp handle_command(:list, _args, state) do
    send_response(state.socket, 500, "Command not implemented")
    state
  end

  defp handle_command(:group, [newsgroup], state) do
    case Protocol.validate_newsgroup_name(newsgroup) do
      :ok ->
        # Fetch forum ID for this newsgroup
        case fetch_forum_for_newsgroup(newsgroup, state) do
          {:ok, forum_id, forum_name} ->
            # Fetch threads for this forum (first page only)
            case fetch_threads_for_forum(forum_id, state) do
              {:ok, threads} ->
                # Calculate article range
                {first, last, count} = calculate_article_range(threads)
                
                # Store group data with threads
                group_data = %{
                  name: newsgroup,
                  forum_id: forum_id,
                  forum_name: forum_name,
                  threads: threads,
                  first: first,
                  last: last,
                  count: count
                }
                
                send_response(state.socket, 211, "#{count} #{first} #{last} #{newsgroup}")
                %{state | current_group: group_data}

              {:error, reason} ->
                Logger.error("Failed to fetch threads: #{inspect(reason)}")
                send_response(state.socket, 411, "No such newsgroup")
                state
            end

          {:error, :not_found} ->
            send_response(state.socket, 411, "No such newsgroup")
            state

          {:error, reason} ->
            Logger.error("Failed to fetch forum list: #{inspect(reason)}")
            send_response(state.socket, 503, "Program error, function not performed")
            state
        end

      {:error, :invalid_format} ->
        send_response(state.socket, 411, "No such newsgroup")
        state
    end
  end

  defp handle_command(:group, _args, state) do
    send_response(state.socket, 501, "Syntax error")
    state
  end

  defp handle_command(:listgroup, [], state) do
    # LISTGROUP with no args - return empty list but acknowledge current group
    case state.current_group do
      nil ->
        send_response(state.socket, 412, "No newsgroup selected")
        state

      group ->
        # Return group info without listing articles (tin will use OVER instead)
        send_multi_line_response(
          state.socket,
          211,
          "#{group.count} #{group.first} #{group.last} #{group.name}",
          []  # Empty list - no article numbers
        )
        state
    end
  end

  defp handle_command(:listgroup, [newsgroup], state) do
    # LISTGROUP with newsgroup - select group but don't list articles
    case Protocol.validate_newsgroup_name(newsgroup) do
      :ok ->
        case fetch_forum_for_newsgroup(newsgroup, state) do
          {:ok, forum_id, forum_name} ->
            case fetch_threads_for_forum(forum_id, state) do
              {:ok, threads} ->
                {first, last, count} = calculate_article_range(threads)
                
                group_data = %{
                  name: newsgroup,
                  forum_id: forum_id,
                  forum_name: forum_name,
                  threads: threads,
                  first: first,
                  last: last,
                  count: count
                }
                
                # Return group info without listing articles
                send_multi_line_response(
                  state.socket,
                  211,
                  "#{count} #{first} #{last} #{newsgroup}",
                  []  # Empty list
                )
                %{state | current_group: group_data}

              {:error, _reason} ->
                send_response(state.socket, 411, "No such newsgroup")
                state
            end

          {:error, _reason} ->
            send_response(state.socket, 411, "No such newsgroup")
            state
        end

      {:error, :invalid_format} ->
        send_response(state.socket, 501, "Syntax error")
        state
    end
  end

  defp handle_command(:article, [], state) do
    # No article number provided
    send_response(state.socket, 420, "Current article number is invalid")
    state
  end

  defp handle_command(:article, [article_spec], state) do
    case parse_article_spec(article_spec) do
      {:article_num, article_num} ->
        fetch_and_send_article(article_num, state)

      {:message_id, _message_id} ->
        # TODO: Support message-id lookup
        send_response(state.socket, 430, "No such article")
        state

      :error ->
        send_response(state.socket, 501, "Syntax error")
        state
    end
  end

  defp handle_command(:over, [], state) do
    Logger.info("OVER with no args - no current article")
    send_response(state.socket, 420, "Current article number is invalid")
    state
  end

  defp handle_command(:over, [range_or_msgid], state) do
    Logger.info("OVER requested: #{range_or_msgid}")
    
    case state.current_group do
      nil ->
        Logger.info("OVER failed - no group selected")
        send_response(state.socket, 412, "No newsgroup selected")
        state

      group ->
        case parse_range(range_or_msgid) do
          {:range, start_num, end_num} ->
            Logger.info("OVER range: #{start_num}-#{end_num}")
            overview_lines = generate_overview_for_range(group, start_num, end_num)
            Logger.info("OVER returning #{length(overview_lines)} results")
            send_multi_line_response(state.socket, 224, "Overview information follows", overview_lines)
            state

          {:single, article_num} ->
            Logger.info("OVER single: #{article_num}")
            overview_lines = generate_overview_for_range(group, article_num, article_num)
            Logger.info("OVER returning #{length(overview_lines)} results")
            send_multi_line_response(state.socket, 224, "Overview information follows", overview_lines)
            state

          {:message_id, _msgid} ->
            send_response(state.socket, 430, "No such article")
            state

          :error ->
            Logger.warning("OVER parse error: #{range_or_msgid}")
            send_response(state.socket, 501, "Syntax error")
            state
        end
    end
  end

  defp handle_command(:xover, args, state) do
    handle_command(:over, args, state)
  end

  # XHDR command - return header field for articles
  defp handle_command(:xhdr, [_header | _rest], state) do
    # Tin uses XHDR to get Xref headers for threading
    # We don't support this - return empty response
    # This tells tin there are no cross-references
    send_multi_line_response(state.socket, 221, "Header follows", [])
    state
  end

  defp handle_command(:xhdr, _args, state) do
    send_response(state.socket, 501, "Syntax error")
    state
  end

  defp handle_command(:authinfo, ["USER", username], state) do
    # Store username and ask for password
    Logger.info("Auth attempt for user: [REDACTED]")
    send_response(state.socket, 381, "Password required")
    %{state | username: username}
  end

  defp handle_command(:authinfo, ["PASS", password], state) do
    # Authenticate with SA using stored username
    case state.username do
      nil ->
        send_response(state.socket, 482, "Authentication rejected - no username provided")
        state

      username ->
        case AwfulNntp.SA.Client.authenticate(username, password) do
          {:ok, sa_client} ->
            Logger.info("Successfully authenticated user with SA")
            send_response(state.socket, 281, "Authentication accepted")
            %{state | authenticated: true, sa_client: sa_client}

          {:error, reason} ->
            Logger.error("Authentication failed: #{inspect(reason)}")
            send_response(state.socket, 481, "Authentication failed")
            state
        end
    end
  end

  defp handle_command(:authinfo, _args, state) do
    send_response(state.socket, 501, "Syntax error")
    state
  end

  defp handle_command(_command, _args, state) do
    send_response(state.socket, 500, "Command not implemented")
    state
  end

  # Helper functions

  # Helper to fetch forum list
  defp fetch_forum_list() do
    client = Req.new(base_url: "https://forums.somethingawful.com")

    with {:ok, response} <- Req.get(client, url: "/"),
         {:ok, forums} <- AwfulNntp.SA.Parser.parse_forum_list(response.body) do
      {:ok, forums}
    else
      {:error, reason} ->
        Logger.error("Failed to fetch forum list: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to find forum ID for a newsgroup
  defp fetch_forum_for_newsgroup(newsgroup, state) do
    # Check cache first
    case Map.get(state.forum_cache, newsgroup) do
      nil ->
        # Fetch forum list and find matching forum
        case fetch_forum_list() do
          {:ok, forums} ->
            case Enum.find(forums, fn forum ->
              AwfulNntp.Mapping.forum_to_newsgroup(forum.name) == newsgroup
            end) do
              nil ->
                {:error, :not_found}
              
              forum ->
                {:ok, forum.id, forum.name}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {forum_id, forum_name} ->
        {:ok, forum_id, forum_name}
    end
  end

  # Helper to fetch threads for a forum (first page only)
  defp fetch_threads_for_forum(forum_id, state) do
    client = case state.sa_client do
      nil ->
        # Use anonymous client
        Req.new(base_url: "https://forums.somethingawful.com")
      
      sa_client ->
        # Use authenticated client
        sa_client
    end

    with {:ok, html} <- AwfulNntp.SA.Client.fetch_forum(client, forum_id),
         {:ok, threads} <- AwfulNntp.SA.Parser.parse_thread_list(html) do
      {:ok, threads}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Calculate article number range from threads (first page only)
  defp calculate_article_range([]), do: {0, 0, 0}
  
  defp calculate_article_range(threads) do
    # Generate article numbers for all posts in all threads
    article_numbers = generate_article_numbers_list(threads)

    first = List.first(article_numbers, 0)
    last = List.last(article_numbers, 0)
    count = length(article_numbers)

    {first, last, count}
  end

  # Generate sorted list of article numbers from threads
  defp generate_article_numbers_list(threads) do
    threads
    |> Enum.flat_map(fn thread ->
      thread_id = String.to_integer(thread.id)
      # Generate article numbers for all posts (replies + 1 for OP)
      num_posts = thread.replies + 1
      Enum.map(1..num_posts, fn post_num ->
        AwfulNntp.Mapping.generate_article_number(thread_id, post_num)
      end)
    end)
    |> Enum.sort()
  end

  # Article handling helpers

  defp parse_article_spec(spec) when is_binary(spec) do
    cond do
      # Message-ID format: <...>
      String.starts_with?(spec, "<") and String.ends_with?(spec, ">") ->
        {:message_id, spec}

      # Article number
      String.match?(spec, ~r/^\d+$/) ->
        case Integer.parse(spec) do
          {num, ""} -> {:article_num, num}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp parse_article_spec(_), do: :error

  defp parse_range(spec) when is_binary(spec) do
    cond do
      String.starts_with?(spec, "<") and String.ends_with?(spec, ">") ->
        {:message_id, spec}

      String.contains?(spec, "-") ->
        case String.split(spec, "-", parts: 2) do
          [start_str, ""] ->
            case Integer.parse(start_str) do
              {start, ""} -> {:range, start, 999_999_999}
              _ -> :error
            end

          [start_str, end_str] ->
            with {start, ""} <- Integer.parse(start_str),
                 {end_num, ""} <- Integer.parse(end_str) do
              {:range, start, end_num}
            else
              _ -> :error
            end

          _ ->
            :error
        end

      String.match?(spec, ~r/^\d+$/) ->
        case Integer.parse(spec) do
          {num, ""} -> {:single, num}
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp parse_range(_), do: :error

  defp generate_overview_for_range(group, start_num, end_num) do
    # Limit overview to prevent memory exhaustion
    # If range is too large, cap it
    max_overview = 1000
    
    group.threads
    |> Enum.flat_map(fn thread ->
      thread_id = String.to_integer(thread.id)
      num_posts = thread.replies + 1

      Enum.map(1..num_posts, fn post_num ->
        article_num = AwfulNntp.Mapping.generate_article_number(thread_id, post_num)

        if article_num >= start_num and article_num <= end_num do
          AwfulNntp.Mapping.format_overview_line(
            thread_id,
            post_num,
            thread.title,
            thread.author
          )
        else
          nil
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(max_overview)  # Limit to first 1000 results
  end

  defp fetch_and_send_article(article_num, state) do
    # Parse article number to get thread_id and post_number
    {thread_id, post_number} = AwfulNntp.Mapping.parse_article_number(article_num)

    Logger.debug("Fetching article #{article_num}: thread=#{thread_id}, post=#{post_number}, authenticated=#{state.authenticated}")

    # Fetch the thread
    client = state.sa_client || Req.new(base_url: "https://forums.somethingawful.com")

    case AwfulNntp.SA.Client.fetch_thread(client, thread_id) do
      {:ok, html} ->
        Logger.debug("Fetched thread HTML: #{String.length(html)} bytes")
        case AwfulNntp.SA.Parser.parse_posts(html) do
          {:ok, posts} ->
            Logger.debug("Parsed #{length(posts)} posts from thread")
            # Get the specific post by number (1-indexed)
            case Enum.at(posts, post_number - 1) do
              nil ->
                send_response(state.socket, 423, "No article with that number")
                state

              post ->
                # Format and send the article
                send_article(state.socket, article_num, thread_id, post, state)
                state
            end

          {:error, reason} ->
            Logger.error("Failed to parse thread posts: #{inspect(reason)}")
            send_response(state.socket, 430, "No such article")
            state
        end

      {:error, reason} ->
        Logger.error("Failed to fetch thread #{thread_id}: #{inspect(reason)}")
        send_response(state.socket, 430, "No such article")
        state
    end
  end

  defp send_article(socket, article_num, thread_id, post, state) do
    # Get thread title from current group if available
    thread_title =
      case state.current_group do
        %{threads: threads} ->
          thread = Enum.find(threads, fn t -> String.to_integer(t.id) == thread_id end)
          if thread, do: thread.title, else: "Thread #{thread_id}"

        _ ->
          "Thread #{thread_id}"
      end

    # Format headers with .invalid domain
    headers = [
      "Path: forums.somethingawful.com",
      "From: #{post.author}@forums.somethingawful.invalid",
      "Newsgroups: #{state.current_group && state.current_group.name || "sa.unknown"}",
      "Subject: #{thread_title}",
      "Date: #{post.date}",
      "Message-ID: #{AwfulNntp.Mapping.generate_message_id(thread_id, post.id)}",
      "Lines: #{count_lines(post.content)}"
    ]

    # Format content (strip HTML)
    content = AwfulNntp.Mapping.format_post_content(post.content)

    # Combine headers and content
    article_lines = headers ++ [""] ++ String.split(content, "\n")

    # Send with ARTICLE response code
    send_multi_line_response(socket, 220, "#{article_num} #{AwfulNntp.Mapping.generate_message_id(thread_id, post.id)}", article_lines)
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  # Helper functions for responses

  defp send_response(socket, code, message) do
    response = Protocol.format_response(code, message)
    :gen_tcp.send(socket, response)
  end

  defp send_multi_line_response(socket, code, message, lines) do
    response = Protocol.format_response(code, message, lines)
    :gen_tcp.send(socket, response)
  end
end
