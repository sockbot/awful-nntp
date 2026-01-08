defmodule AwfulNntp.NNTP.ConnectionTest do
  use ExUnit.Case, async: true

  alias AwfulNntp.NNTP.Connection

  setup do
    # Create a mock socket pair for testing
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, packet: :line, active: false])
    {:ok, port} = :inet.port(listen_socket)

    # Connect client socket
    {:ok, client_socket} = :gen_tcp.connect(~c"localhost", port, [:binary, packet: :line, active: false])

    # Accept server socket
    {:ok, server_socket} = :gen_tcp.accept(listen_socket)

    # Start connection handler
    {:ok, pid} = Connection.start_link(server_socket)
    
    # Transfer socket control to the connection process (like the real server does)
    :ok = :gen_tcp.controlling_process(server_socket, pid)

    # Read welcome banner
    {:ok, banner} = :gen_tcp.recv(client_socket, 0, 1000)
    assert banner =~ "200 awful-nntp ready"

    on_exit(fn ->
      :gen_tcp.close(listen_socket)
      :gen_tcp.close(client_socket)
    end)

    {:ok, client: client_socket, server: pid}
  end

  describe "CAPABILITIES command" do
    test "returns capability list", %{client: client} do
      :gen_tcp.send(client, "CAPABILITIES\r\n")

      # Read response code
      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "101 Capability list"

      # Read capabilities - now includes OVER
      {:ok, version} = :gen_tcp.recv(client, 0, 1000)
      assert version =~ "VERSION 2"

      {:ok, reader} = :gen_tcp.recv(client, 0, 1000)
      assert reader =~ "READER"

      {:ok, list} = :gen_tcp.recv(client, 0, 1000)
      assert list =~ "LIST ACTIVE"

      {:ok, over} = :gen_tcp.recv(client, 0, 1000)
      assert over =~ "OVER"

      {:ok, authinfo} = :gen_tcp.recv(client, 0, 1000)
      assert authinfo =~ "AUTHINFO USER"

      # Read terminator
      {:ok, terminator} = :gen_tcp.recv(client, 0, 1000)
      assert terminator == ".\r\n"
    end
  end

  describe "QUIT command" do
    test "closes connection gracefully", %{client: client} do
      :gen_tcp.send(client, "QUIT\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "205 Closing connection"

      # Connection should close
      assert :gen_tcp.recv(client, 0, 1000) == {:error, :closed}
    end
  end

  describe "LIST command" do
    # TODO: Mock SA HTTP requests instead of making real network calls
    @tag :skip
    test "returns newsgroups list", %{client: client} do
      :gen_tcp.send(client, "LIST\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 5000)
      assert response =~ "215 Newsgroups follow"

      # Read until terminator (should get at least the terminator)
      lines = read_until_terminator(client, 5000)
      assert List.last(lines) == ".\r\n"
    end
  end

  describe "GROUP command" do
    # TODO: Mock SA HTTP requests to avoid real network calls
    @tag :skip
    test "accepts valid newsgroup", %{client: client} do
      :gen_tcp.send(client, "GROUP sa.general-bullshit\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "211"
      assert response =~ "sa.general-bullshit"
    end

    test "rejects invalid newsgroup", %{client: client} do
      :gen_tcp.send(client, "GROUP invalid\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "411 No such newsgroup"
    end

    test "rejects GROUP without argument", %{client: client} do
      :gen_tcp.send(client, "GROUP\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "501 Syntax error"
    end
  end

  describe "ARTICLE command" do
    test "returns error for nonexistent article", %{client: client} do
      :gen_tcp.send(client, "ARTICLE 123456\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      # May return 412 (no group selected), 423 (no article with that number) or 430 (no such article)
      assert response =~ ~r/4(12|23|30)/
    end

    test "returns error without argument", %{client: client} do
      :gen_tcp.send(client, "ARTICLE\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "420 Current article number is invalid"
    end
  end

  describe "AUTHINFO command" do
    test "handles USER command", %{client: client} do
      :gen_tcp.send(client, "AUTHINFO USER testuser\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "381 Password required"
    end

    # TODO: Mock SA authentication to avoid real network calls
    @tag :skip
    test "handles PASS command with invalid credentials", %{client: client} do
      :gen_tcp.send(client, "AUTHINFO USER testuser\r\n")
      {:ok, _} = :gen_tcp.recv(client, 0, 1000)

      :gen_tcp.send(client, "AUTHINFO PASS password\r\n")
      {:ok, response} = :gen_tcp.recv(client, 0, 5000)
      # Should fail with fake credentials
      assert response =~ "481 Authentication failed"
    end

    test "rejects PASS without USER", %{client: client} do
      :gen_tcp.send(client, "AUTHINFO PASS password\r\n")
      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "482 Authentication rejected"
    end

    test "rejects AUTHINFO with invalid syntax", %{client: client} do
      :gen_tcp.send(client, "AUTHINFO INVALID\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "501 Syntax error"
    end
  end

  describe "unknown commands" do
    test "returns error for unknown command", %{client: client} do
      :gen_tcp.send(client, "INVALID\r\n")

      {:ok, response} = :gen_tcp.recv(client, 0, 1000)
      assert response =~ "500"
    end
  end

  # Helper function to read multi-line responses
  defp read_until_terminator(socket, acc \\ []) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, ".\r\n"} ->
        Enum.reverse([".\r\n" | acc])

      {:ok, line} ->
        read_until_terminator(socket, [line | acc])

      {:error, _} ->
        Enum.reverse(acc)
    end
  end
end
