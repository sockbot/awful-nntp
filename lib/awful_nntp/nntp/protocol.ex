defmodule AwfulNntp.NNTP.Protocol do
  @moduledoc """
  NNTP protocol parser and formatter.
  Implements RFC 3977 command parsing and response formatting.
  """

  @type command ::
          :capabilities
          | :quit
          | :group
          | :article
          | :head
          | :body
          | :stat
          | :list
          | :listgroup
          | :post
          | :authinfo
          | :over
          | :xover

  @type parse_result :: {:ok, command(), [String.t()]} | {:error, atom()}

  @doc """
  Parses an NNTP command from a client.

  ## Examples

      iex> AwfulNntp.NNTP.Protocol.parse_command("CAPABILITIES\\r\\n")
      {:ok, :capabilities, []}

      iex> AwfulNntp.NNTP.Protocol.parse_command("GROUP sa.general-bullshit\\r\\n")
      {:ok, :group, ["sa.general-bullshit"]}
  """
  @spec parse_command(String.t()) :: parse_result()
  def parse_command(line) when is_binary(line) do
    line
    |> String.trim()
    |> case do
      "" -> {:error, :empty_command}
      trimmed -> do_parse_command(trimmed)
    end
  end

  defp do_parse_command(line) do
    # Split into command and args, preserving case for args
    case String.split(line, ~r/\s+/, parts: 2, trim: true) do
      [cmd] ->
        parse_command_parts(String.upcase(cmd), [])

      [cmd, args_str] ->
        cmd_upper = String.upcase(cmd)
        # For AUTHINFO, preserve case of first arg (USER/PASS) but uppercase it
        # For other commands, preserve original case
        args =
          if cmd_upper == "AUTHINFO" do
            case String.split(args_str, ~r/\s+/, parts: 2, trim: true) do
              [subcommand] -> [String.upcase(subcommand)]
              [subcommand, value] -> [String.upcase(subcommand), value]
              _ -> []
            end
          else
            String.split(args_str, ~r/\s+/, trim: true)
          end

        parse_command_parts(cmd_upper, args)

      _ ->
        {:error, :empty_command}
    end
  end

  defp parse_command_parts(cmd, args) do
    case cmd do
      "CAPABILITIES" -> {:ok, :capabilities, []}
      "QUIT" -> {:ok, :quit, []}
      "LIST" -> {:ok, :list, args}
      "GROUP" -> {:ok, :group, args}
      "LISTGROUP" -> {:ok, :listgroup, args}
      "ARTICLE" -> {:ok, :article, args}
      "HEAD" -> {:ok, :head, args}
      "BODY" -> {:ok, :body, args}
      "STAT" -> {:ok, :stat, args}
      "POST" -> {:ok, :post, args}
      "AUTHINFO" -> {:ok, :authinfo, args}
      "OVER" -> {:ok, :over, args}
      "XOVER" -> {:ok, :xover, args}
      _ -> {:error, :unknown_command}
    end
  end

  @doc """
  Formats an NNTP response code and message.

  ## Examples

      iex> AwfulNntp.NNTP.Protocol.format_response(200, "Service available")
      "200 Service available\\r\\n"
  """
  @spec format_response(integer(), String.t()) :: String.t()
  def format_response(code, message) when is_integer(code) and is_binary(message) do
    "#{code} #{message}\r\n"
  end

  @doc """
  Formats an NNTP multi-line response.

  ## Examples

      iex> AwfulNntp.NNTP.Protocol.format_response(215, "List follows", ["sa.games 100 1 y"])
      "215 List follows\\r\\nsa.games 100 1 y\\r\\n.\\r\\n"
  """
  @spec format_response(integer(), String.t(), [String.t()]) :: String.t()
  def format_response(code, message, lines)
      when is_integer(code) and is_binary(message) and is_list(lines) do
    header = "#{code} #{message}\r\n"
    body = Enum.map_join(lines, "\r\n", & &1)
    terminator = ".\r\n"

    case lines do
      [] -> header <> terminator
      _ -> header <> body <> "\r\n" <> terminator
    end
  end

  @doc """
  Validates a newsgroup name according to our naming convention.
  
  Valid format: sa.<forum-name>
  
  ## Examples
  
      iex> AwfulNntp.NNTP.Protocol.validate_newsgroup_name("sa.general-bullshit")
      :ok
      
      iex> AwfulNntp.NNTP.Protocol.validate_newsgroup_name("invalid")
      {:error, :invalid_format}
  """
  @spec validate_newsgroup_name(String.t()) :: :ok | {:error, :invalid_format}
  def validate_newsgroup_name(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      ["sa", forum_name] when byte_size(forum_name) > 0 ->
        if valid_forum_name?(forum_name) do
          :ok
        else
          {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp valid_forum_name?(name) do
    # Valid characters: lowercase letters, hyphens, numbers
    String.match?(name, ~r/^[a-z0-9][a-z0-9\-]*[a-z0-9]$/)
  end
end
