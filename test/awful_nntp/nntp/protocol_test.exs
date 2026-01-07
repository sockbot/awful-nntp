defmodule AwfulNntp.NNTP.ProtocolTest do
  use ExUnit.Case, async: true

  alias AwfulNntp.NNTP.Protocol

  describe "parse_command/1" do
    test "parses CAPABILITIES command" do
      assert Protocol.parse_command("CAPABILITIES\r\n") == {:ok, :capabilities, []}
    end

    test "parses QUIT command" do
      assert Protocol.parse_command("QUIT\r\n") == {:ok, :quit, []}
    end

    test "parses GROUP command with argument" do
      assert Protocol.parse_command("GROUP sa.general-bullshit\r\n") ==
               {:ok, :group, ["sa.general-bullshit"]}
    end

    test "parses ARTICLE command with number" do
      assert Protocol.parse_command("ARTICLE 12345\r\n") == {:ok, :article, ["12345"]}
    end

    test "parses LIST command" do
      assert Protocol.parse_command("LIST\r\n") == {:ok, :list, []}
    end

    test "parses AUTHINFO USER command" do
      assert Protocol.parse_command("AUTHINFO USER testuser\r\n") ==
               {:ok, :authinfo, ["USER", "testuser"]}
    end

    test "parses AUTHINFO PASS command" do
      assert Protocol.parse_command("AUTHINFO PASS secret123\r\n") ==
               {:ok, :authinfo, ["PASS", "secret123"]}
    end

    test "handles commands without CRLF" do
      assert Protocol.parse_command("CAPABILITIES") == {:ok, :capabilities, []}
    end

    test "handles lowercase commands" do
      assert Protocol.parse_command("quit\r\n") == {:ok, :quit, []}
    end

    test "handles extra whitespace" do
      assert Protocol.parse_command("  GROUP   sa.test  \r\n") == {:ok, :group, ["sa.test"]}
    end

    test "returns error for unknown command" do
      assert Protocol.parse_command("INVALID\r\n") == {:error, :unknown_command}
    end

    test "returns error for empty input" do
      assert Protocol.parse_command("") == {:error, :empty_command}
    end
  end

  describe "format_response/2" do
    test "formats simple response" do
      assert Protocol.format_response(200, "Service available") ==
               "200 Service available\r\n"
    end

    test "formats multi-line response" do
      lines = ["sa.general-bullshit 1000 1 y", "sa.games 500 1 y"]
      response = Protocol.format_response(215, "Newsgroups follow", lines)

      assert response == """
             215 Newsgroups follow\r
             sa.general-bullshit 1000 1 y\r
             sa.games 500 1 y\r
             .\r
             """
    end

    test "formats response with empty body" do
      assert Protocol.format_response(215, "List follows", []) ==
               "215 List follows\r\n.\r\n"
    end
  end

  describe "validate_newsgroup_name/1" do
    test "accepts valid newsgroup names" do
      assert Protocol.validate_newsgroup_name("sa.general-bullshit") == :ok
      assert Protocol.validate_newsgroup_name("sa.games") == :ok
      assert Protocol.validate_newsgroup_name("sa.ask-tell") == :ok
    end

    test "rejects invalid newsgroup names" do
      assert Protocol.validate_newsgroup_name("invalid") == {:error, :invalid_format}
      assert Protocol.validate_newsgroup_name("sa") == {:error, :invalid_format}
      assert Protocol.validate_newsgroup_name("sa.") == {:error, :invalid_format}
      assert Protocol.validate_newsgroup_name("") == {:error, :invalid_format}
    end

    test "rejects newsgroups with invalid characters" do
      assert Protocol.validate_newsgroup_name("sa.test@invalid") == {:error, :invalid_format}
      assert Protocol.validate_newsgroup_name("sa.test space") == {:error, :invalid_format}
    end
  end
end
