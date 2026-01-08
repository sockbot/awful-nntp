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
        # For each forum, we need to fetch thread counts to report article numbers
        # But that's expensive, so for LIST we'll report placeholder numbers
        # Clients will get real numbers when they use GROUP
        lines =
          forums
          |> Enum.map(fn forum ->
            newsgroup = AwfulNntp.Mapping.forum_to_newsgroup(forum.name)
            # Format: newsgroup high low status
            # Use 1 1 y to indicate group has articles (tin needs high > 0)
            "#{newsgroup} 1 1 y"
          end)

        send_multi_line_response(state.socket, 215, "Newsgroups follow", lines)
        state

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

  defp handle_command(:list, ["NEWSGROUPS"], state) do
    # Return newsgroups with descriptions
    case fetch_forum_list() do
      {:ok, forums} ->
        lines =
          forums
          |> Enum.map(fn forum ->
            newsgroup = AwfulNntp.Mapping.forum_to_newsgroup(forum.name)
            # Format: newsgroup description
            description = forum.description || forum.name
            "#{newsgroup} #{description}"
          end)

        send_multi_line_response(state.socket, 215, "Newsgroups follow", lines)
        state

      {:error, _reason} ->
        send_multi_line_response(state.socket, 215, "Newsgroups follow", [])
        state
    end
  end

  defp handle_command(:list, _args, state) do
    send_response(state.socket, 500, "Command not implemented")
    state
  end

  defp handle_command(:group, [newsgroup], state) do
    Logger.info("GROUP command for: #{newsgroup}")
    case Protocol.validate_newsgroup_name(newsgroup) do
      :ok ->
        # Fetch forum ID for this newsgroup
        case fetch_forum_for_newsgroup(newsgroup, state) do
          {:ok, forum_id, forum_name} ->
            Logger.info("Found forum: #{forum_name} (ID: #{forum_id})")
            # Fetch threads for this forum (first page only)
            case fetch_threads_for_forum(forum_id, state) do
              {:ok, threads} ->
                Logger.info("Fetched #{length(threads)} threads")
                # Build sequential article number mapping
                {article_map, first, last, count} = AwfulNntp.Mapping.build_article_map(threads)
                
                # Store group data with threads and article mapping
                group_data = %{
                  name: newsgroup,
                  forum_id: forum_id,
                  forum_name: forum_name,
                  threads: threads,
                  article_map: article_map,
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
    # LISTGROUP with no args - return limited list of article numbers for current group
    case state.current_group do
      nil ->
        send_response(state.socket, 412, "No newsgroup selected")
        state

      group ->
        # Generate article numbers - limit to first 1000 to avoid excessive output
        article_numbers = 
          group.first..min(group.first + 999, group.last)
          |> Enum.map(&Integer.to_string/1)
        
        send_multi_line_response(
          state.socket,
          211,
          "#{group.count} #{group.first} #{group.last} #{group.name}",
          article_numbers
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
                # Build sequential article number mapping
                {article_map, first, last, count} = AwfulNntp.Mapping.build_article_map(threads)
                
                group_data = %{
                  name: newsgroup,
                  forum_id: forum_id,
                  forum_name: forum_name,
                  threads: threads,
                  article_map: article_map,
                  first: first,
                  last: last,
                  count: count
                }
                
                # Return group info with limited article list (first 1000)
                article_numbers = 
                  first..min(first + 999, last)
                  |> Enum.map(&Integer.to_string/1)
                
                send_multi_line_response(
                  state.socket,
                  211,
                  "#{count} #{first} #{last} #{newsgroup}",
                  article_numbers
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
  defp handle_command(:xhdr, [], state) do
    # XHDR with no args - invalid but return empty to keep tin happy
    send_multi_line_response(state.socket, 221, "Header follows", [])
    state
  end

  defp handle_command(:xhdr, [header | rest], state) do
    # XHDR header [range|msgid]
    # Tin uses XHDR to get headers for threading
    # We need to return actual data for articles that exist
    
    case state.current_group do
      nil ->
        send_response(state.socket, 412, "No newsgroup selected")
        state
      
      group ->
        # Parse range if provided
        range_result = case rest do
          [] -> {:single, group.first}  # Current article
          [range_spec] -> parse_range(range_spec)
        end
        
        case range_result do
          {:range, start_num, end_num} ->
            lines = generate_xhdr_for_range(group, header, start_num, end_num)
            send_multi_line_response(state.socket, 221, "#{header} header follows", lines)
            state
          
          {:single, article_num} ->
            lines = generate_xhdr_for_range(group, header, article_num, article_num)
            send_multi_line_response(state.socket, 221, "#{header} header follows", lines)
            state
          
          _ ->
            send_response(state.socket, 501, "Syntax error")
            state
        end
    end
  end
  
  defp generate_xhdr_for_range(group, header, start_num, end_num) do
    # Generate XHDR response: "article_num header_value"
    # For XREF: format is "article_num groupname:article_num"
    max_results = 100
    
    start_num..end_num
    |> Enum.take(max_results)
    |> Enum.map(fn article_num ->
      if Map.has_key?(group.article_map, article_num) do
        case String.upcase(header) do
          "XREF" ->
            # XREF format: "article_num hostname groupname:article_num"
            "#{article_num} forums.somethingawful.com #{group.name}:#{article_num}"
          
          _ ->
            # For other headers, just return empty
            nil
        end
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
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

  # Helper to fetch threads for a forum (multiple pages)
  defp fetch_threads_for_forum(forum_id, state, max_pages \\ 3) do
    client = case state.sa_client do
      nil ->
        # Use anonymous client
        Req.new(base_url: "https://forums.somethingawful.com")
      
      sa_client ->
        # Use authenticated client
        sa_client
    end

    # Fetch multiple pages and combine results
    pages = 1..max_pages
    
    threads = Enum.reduce_while(pages, [], fn page, acc ->
      case AwfulNntp.SA.Client.fetch_forum(client, forum_id, page) do
        {:ok, html} ->
          case AwfulNntp.SA.Parser.parse_thread_list(html) do
            {:ok, []} ->
              # Empty page, stop fetching
              {:halt, acc}
            
            {:ok, page_threads} ->
              # Got threads, add them and continue
              {:cont, acc ++ page_threads}
            
            {:error, _reason} ->
              # Parse error, stop and return what we have
              {:halt, acc}
          end
        
        {:error, _reason} ->
          # Fetch error, stop and return what we have
          {:halt, acc}
      end
    end)
    
    if length(threads) > 0 do
      {:ok, threads}
    else
      {:error, :no_threads}
    end
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
    # Use the article_map to look up thread_id and post_num for each article number
    # Only generate overviews for articles that actually exist in the map
    max_overview = 1000
    
    start_num..end_num
    |> Enum.take(max_overview)
    |> Enum.map(fn article_num ->
      case Map.get(group.article_map, article_num) do
        {thread_id, post_num} ->
          # Find the thread for this article
          thread = Enum.find(group.threads, fn t -> String.to_integer(t.id) == thread_id end)
          
          if thread do
            AwfulNntp.Mapping.format_overview_line(
              article_num,
              thread_id,
              post_num,
              thread.title,
              thread.author
            )
          else
            nil
          end
        
        nil ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_and_send_article(article_num, state) do
    # Look up article in the current group's article map
    case state.current_group do
      nil ->
        send_response(state.socket, 412, "No newsgroup selected")
        state
      
      group ->
        case Map.get(group.article_map, article_num) do
          nil ->
            send_response(state.socket, 423, "No such article in group")
            state
          
          {thread_id, post_number} ->
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
