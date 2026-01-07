defmodule AwfulNntp.NNTP.Server do
  @moduledoc """
  TCP server that listens for NNTP client connections.
  Spawns a new Connection process for each client.
  """

  require Logger

  @default_port 1199

  @doc """
  Starts the NNTP TCP server.
  """
  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    Task.start_link(__MODULE__, :accept_loop, [port])
  end

  @doc """
  Main accept loop - listens for incoming connections.
  """
  def accept_loop(port) do
    {:ok, listen_socket} =
      :gen_tcp.listen(port, [
        :binary,
        packet: :line,
        active: false,
        reuseaddr: true
      ])

    Logger.info("NNTP server listening on port #{port}")
    accept_connections(listen_socket)
  end

  defp accept_connections(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        {:ok, {address, port}} = :inet.peername(client_socket)
        Logger.info("New connection from #{:inet.ntoa(address)}:#{port}")

        # Spawn connection handler
        {:ok, pid} =
          DynamicSupervisor.start_child(
            AwfulNntp.ConnectionSupervisor,
            {AwfulNntp.NNTP.Connection, client_socket}
          )

        # Transfer socket control to the connection process
        :ok = :gen_tcp.controlling_process(client_socket, pid)

        accept_connections(listen_socket)

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        accept_connections(listen_socket)
    end
  end
end
