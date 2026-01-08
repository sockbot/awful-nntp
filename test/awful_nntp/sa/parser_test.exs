defmodule AwfulNntp.SA.ParserTest do
  use ExUnit.Case, async: true

  alias AwfulNntp.SA.Parser

  describe "parse_forum_list/1" do
    test "parses forum list from HTML" do
      html = """
      <html>
        <tr class="forum forum_273">
          <td class="icon">
            <a href="forumdisplay.php?forumid=273"><img src="icon.gif" alt=""></a>
          </td>
          <td class="title">
            <a class="forum" href="forumdisplay.php?forumid=273">General Bullshit</a>
            <span class="forumdesc"> - This is the general discussion forum.</span>
          </td>
        </tr>
        <tr class="forum forum_44">
          <td class="icon">
            <a href="forumdisplay.php?forumid=44"><img src="icon.gif" alt=""></a>
          </td>
          <td class="title">
            <a class="forum" href="forumdisplay.php?forumid=44">Games</a>
            <span class="forumdesc"> - Video games discussion.</span>
          </td>
        </tr>
      </html>
      """

      assert {:ok, forums} = Parser.parse_forum_list(html)
      assert length(forums) == 2
      assert Enum.any?(forums, fn f -> f.name == "General Bullshit" && f.id == "273" end)
      assert Enum.any?(forums, fn f -> f.name == "Games" && f.id == "44" end)
    end

    test "returns empty list for no forums" do
      html = "<html><body>No forums</body></html>"
      assert {:ok, []} = Parser.parse_forum_list(html)
    end
  end

  describe "parse_thread_list/1" do
    test "parses thread list from HTML" do
      html = """
      <html>
        <tr class="thread" id="thread12345">
          <td class="title">
            <a href="showthread.php?threadid=12345" class="thread_title">Test Thread</a>
          </td>
          <td class="author"><a href="">TestUser</a></td>
          <td class="replies"><a href="">42</a></td>
        </tr>
      </html>
      """

      assert {:ok, threads} = Parser.parse_thread_list(html)
      assert length(threads) == 1
      thread = List.first(threads)
      assert thread.id == "12345"
      assert thread.title == "Test Thread"
      assert thread.author == "TestUser"
      assert thread.replies == 42
    end
  end

  describe "parse_posts/1" do
    test "parses posts from thread" do
      html = """
      <html>
        <table class="post" id="post67890">
          <dt class="author">PostAuthor</dt>
          <dd class="postdate">Jan 01, 2026</dd>
          <td class="postbody">Post content here</td>
        </table>
      </html>
      """

      assert {:ok, posts} = Parser.parse_posts(html)
      assert length(posts) == 1
      post = List.first(posts)
      assert post.id == "67890"
      assert post.author == "PostAuthor"
    end
  end
end
