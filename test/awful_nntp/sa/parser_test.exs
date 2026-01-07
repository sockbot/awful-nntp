defmodule AwfulNntp.SA.ParserTest do
  use ExUnit.Case, async: true

  alias AwfulNntp.SA.Parser

  describe "parse_forum_list/1" do
    test "parses forum list from HTML" do
      html = """
      <html>
        <div class="forum">
          <a href="/forumdisplay.php?forumid=1">General Bullshit</a>
        </div>
        <div class="forum">
          <a href="/forumdisplay.php?forumid=44">Games</a>
        </div>
      </html>
      """

      # This will fail until we implement it - TDD!
      assert {:ok, forums} = Parser.parse_forum_list(html)
      assert length(forums) == 2
      assert Enum.any?(forums, fn f -> f.name == "General Bullshit" && f.id == "1" end)
      assert Enum.any?(forums, fn f -> f.name == "Games" && f.id == "44" end)
    end

    test "returns empty list for no forums" do
      html = "<html><body>No forums</body></html>"
      assert {:ok, []} = Parser.parse_forum_list(html)
    end
  end

  describe "parse_thread_list/1" do
    test "parses thread list from HTML" do
      # TODO: Add test once we define the HTML structure
      assert true
    end
  end

  describe "parse_post/1" do
    test "parses post content from HTML" do
      # TODO: Add test once we define the HTML structure
      assert true
    end
  end
end
