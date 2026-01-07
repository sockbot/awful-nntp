defmodule AwfulNntp.NNTP.Connection do
  @moduledoc """
  GenServer that handles a single NNTP client connection.
  Processes commands and sends responses.
  """

  use GenServer
  require Logger

  alias AwfulNntp.NNTP.Protocol

  defstruct [:socket, :current_group, :authenticated]

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
      authenticated: false
    }

    # Send welcome banner
    send_response(socket, 200, "awful-nntp ready (posting ok)")

    {:ok, state}
  end

  @impl true
  def handle_info({:tcp, socket, data}, state) do
    case Protocol.parse_command(data) do
      {:ok, command, args} ->
        Logger.debug("Command received: #{command} #{inspect(args)}")
        new_state = handle_command(command, args, state)
        {:noreply, new_state}

      {:error, :empty_command} ->
        {:noreply, state}

      {:error, :unknown_command} ->
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
      "LIST ACTIVE",
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

  defp handle_command(:list, _args, state) do
    # TODO: Fetch actual forums from SA
    # For now, return empty list
    send_multi_line_response(state.socket, 215, "Newsgroups follow", [])
    state
  end

  defp handle_command(:group, [newsgroup], state) do
    case Protocol.validate_newsgroup_name(newsgroup) do
      :ok ->
        # TODO: Fetch actual group info from SA
        # For now, return placeholder
        send_response(state.socket, 211, "0 0 0 #{newsgroup}")
        %{state | current_group: newsgroup}

      {:error, :invalid_format} ->
        send_response(state.socket, 411, "No such newsgroup")
        state
    end
  end

  defp handle_command(:group, _args, state) do
    send_response(state.socket, 501, "Syntax error")
    state
  end

  defp handle_command(:article, _args, state) do
    send_response(state.socket, 430, "No such article")
    state
  end

  defp handle_command(:authinfo, ["USER", username], state) do
    # Store username and ask for password
    Logger.info("Auth attempt for user: #{username}")
    send_response(state.socket, 381, "Password required")
    state
  end

  defp handle_command(:authinfo, ["PASS", _password], state) do
    # TODO: Implement actual SA authentication
    send_response(state.socket, 281, "Authentication accepted")
    %{state | authenticated: true}
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

  defp send_response(socket, code, message) do
    response = Protocol.format_response(code, message)
    :gen_tcp.send(socket, response)
  end

  defp send_multi_line_response(socket, code, message, lines) do
    response = Protocol.format_response(code, message, lines)
    :gen_tcp.send(socket, response)
  end
end
