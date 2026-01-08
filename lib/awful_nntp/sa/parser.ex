defmodule AwfulNntp.SA.Parser do
  @moduledoc """
  HTML parser for Something Awful forums.
  Extracts forum lists, threads, and posts from SA HTML.
  """

  @doc """
  Parses the forum list from the main forums page.
  
  Returns a list of forum maps with:
  - id: Forum ID (string)
  - name: Forum name
  - description: Forum description (optional)
  """
  def parse_forum_list(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        forums =
          document
          |> Floki.find("tr.forum")
          |> Enum.map(&extract_forum/1)
          |> Enum.reject(&is_nil/1)

        {:ok, forums}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a forum's thread list.
  
  Returns a list of thread maps with:
  - id: Thread ID (string)
  - title: Thread title
  - author: Username of thread author
  - replies: Number of replies
  - sticky: Boolean if sticky thread
  - closed: Boolean if closed thread
  """
  def parse_thread_list(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        threads =
          document
          |> Floki.find("tr.thread")
          |> Enum.map(&extract_thread/1)
          |> Enum.reject(&is_nil/1)

        {:ok, threads}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a thread's posts.
  
  Returns a list of post maps with:
  - id: Post ID (string)
  - author: Username
  - date: Post timestamp
  - content: Post HTML content
  """
  def parse_posts(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        posts =
          document
          |> Floki.find("table.post")
          |> Enum.map(&extract_post/1)
          |> Enum.reject(&is_nil/1)

        {:ok, posts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp extract_forum(forum_row) do
    # Extract forum ID from class attribute
    forum_id =
      forum_row
      |> Floki.attribute("class")
      |> List.first()
      |> extract_forum_id()

    # Extract forum name and URL
    forum_link =
      forum_row
      |> Floki.find("td.title a.forum")
      |> List.first()

    case forum_link do
      nil ->
        nil

      link ->
        name = Floki.text(link)
        href = Floki.attribute(link, "href") |> List.first()

        # Extract description
        description =
          forum_row
          |> Floki.find("span.forumdesc")
          |> Floki.text()
          |> String.trim()
          |> String.trim_leading("-")
          |> String.trim()

        %{
          id: forum_id,
          name: name,
          description: description,
          href: href
        }
    end
  end

  defp extract_forum_id(class_string) when is_binary(class_string) do
    case Regex.run(~r/forum_(\d+)/, class_string) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp extract_forum_id(_), do: nil

  defp extract_thread(thread_row) do
    # Extract thread ID from id attribute
    thread_id =
      thread_row
      |> Floki.attribute("id")
      |> List.first()
      |> extract_thread_id()

    # Extract title and link
    title_link =
      thread_row
      |> Floki.find("a.thread_title")
      |> List.first()

    case title_link do
      nil ->
        nil

      link ->
        title = Floki.text(link)

        # Extract author
        author =
          thread_row
          |> Floki.find("td.author a")
          |> Floki.text()

        # Extract reply count
        replies =
          thread_row
          |> Floki.find("td.replies a")
          |> Floki.text()
          |> String.to_integer()

        # Check if sticky or closed
        classes = Floki.attribute(thread_row, "class") |> List.first() || ""
        sticky = String.contains?(classes, "sticky")
        closed = String.contains?(classes, "closed")

        %{
          id: thread_id,
          title: title,
          author: author,
          replies: replies,
          sticky: sticky,
          closed: closed
        }
    end
  end

  defp extract_thread_id("thread" <> id), do: id
  defp extract_thread_id(_), do: nil

  defp extract_post(post_table) do
    # Extract post ID from id attribute
    post_id =
      post_table
      |> Floki.attribute("id")
      |> List.first()
      |> extract_post_id()

    # Extract author
    author =
      post_table
      |> Floki.find("dt.author")
      |> Floki.text()
      |> String.trim()

    # Extract date from td.postdate
    # The date text is after the links, format: "Jan  8, 2026 06:13"
    date_text =
      post_table
      |> Floki.find("td.postdate")
      |> Floki.text()
      |> String.trim()
      |> String.replace(~r/#\?/, "")  # Remove #? from link text
      |> String.trim()
    
    # Parse and convert to RFC 5322 format
    date = parse_sa_date(date_text)

    # Extract post content
    content =
      post_table
      |> Floki.find("td.postbody")
      |> Floki.raw_html()

    case post_id do
      nil ->
        nil

      id ->
        %{
          id: id,
          author: author,
          date: date,
          content: content
        }
    end
  end

  defp extract_post_id("post" <> id), do: id
  defp extract_post_id(_), do: nil
  
  # Parse SA date format: "Jan  8, 2026 06:13" to RFC 5322
  defp parse_sa_date(date_string) when is_binary(date_string) do
    # SA format: "Mon DD, YYYY HH:MM" (with possible double space)
    # Example: "Jan  8, 2026 06:13"
    case Regex.run(~r/(\w{3})\s+(\d+),\s+(\d{4})\s+(\d{2}):(\d{2})/, date_string) do
      [_, month, day, year, hour, min] ->
        # Convert to RFC 5322: "Day, DD Mon YYYY HH:MM:SS +0000"
        # We don't have day of week or timezone from SA, so we'll calculate day and assume UTC
        day_padded = String.pad_leading(day, 2, " ")
        "#{month} #{day_padded}, #{year} #{hour}:#{min}:00 +0000"
      
      nil ->
        # Fallback to current time if parse fails
        now = DateTime.utc_now()
        Calendar.strftime(now, "%b %d, %Y %H:%M:%S +0000")
    end
  end
  
  defp parse_sa_date(_), do: ""
end
