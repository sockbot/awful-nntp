defmodule AwfulNntp.Mapping do
  @moduledoc """
  Maps between SA forum data and NNTP structures.
  """

  @doc """
  Converts SA forum name to NNTP newsgroup name.
  
  ## Examples
  
      iex> AwfulNntp.Mapping.forum_to_newsgroup("General Bullshit")
      "sa.general-bullshit"
      
      iex> AwfulNntp.Mapping.forum_to_newsgroup("Ask / Tell")
      "sa.ask-tell"
  """
  def forum_to_newsgroup(forum_name) do
    "sa." <>
      (forum_name
       |> String.downcase()
       |> String.replace(~r/[^a-z0-9]+/, "-")
       |> String.trim("-"))
  end

  @doc """
  Converts NNTP newsgroup name back to SA forum ID lookup.
  Returns just the slug part (without 'sa.' prefix).
  """
  def newsgroup_to_forum_slug(newsgroup) do
    String.replace_prefix(newsgroup, "sa.", "")
  end

  @doc """
  Generates NNTP article number from thread ID and post position.
  
  Article number format: thread_id * 1000000 + post_number
  This ensures unique, sequential article numbers per forum.
  """
  def generate_article_number(thread_id, post_number) when is_integer(thread_id) do
    thread_id * 1_000_000 + post_number
  end

  def generate_article_number(thread_id, post_number) when is_binary(thread_id) do
    thread_id
    |> String.to_integer()
    |> generate_article_number(post_number)
  end

  @doc """
  Parses article number back into thread ID and post number.
  """
  def parse_article_number(article_number) when is_integer(article_number) do
    thread_id = div(article_number, 1_000_000)
    post_number = rem(article_number, 1_000_000)
    {thread_id, post_number}
  end

  def parse_article_number(article_number) when is_binary(article_number) do
    article_number
    |> String.to_integer()
    |> parse_article_number()
  end

  @doc """
  Generates Message-ID for a post.
  Format: <post_id.thread_id@forums.somethingawful.com>
  """
  def generate_message_id(thread_id, post_id) do
    "<#{post_id}.#{thread_id}@forums.somethingawful.com>"
  end

  @doc """
  Formats SA post data as NNTP article headers.
  """
  def format_article_headers(thread_id, post, _post_number) do
    [
      "Path: forums.somethingawful.com",
      "From: #{post.author}@somethingawful.com",
      "Newsgroups: sa.forum",
      # TODO: Use actual thread title
      "Subject: Thread #{thread_id}",
      "Date: #{format_date(post.date)}",
      "Message-ID: #{generate_message_id(thread_id, post.id)}",
      "Lines: #{count_lines(post.content)}"
    ]
  end

  @doc """
  Strips HTML and formats post content for NNTP.
  """
  def format_post_content(html_content) do
    # Simple HTML stripping for now
    html_content
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.trim()
  end

  @doc """
  Formats a thread as an OVER (overview) line.
  
  OVER format (tab-separated):
  article_num<TAB>subject<TAB>from<TAB>date<TAB>message-id<TAB>references<TAB>:bytes<TAB>:lines
  
  For SA threads, we'll generate one overview line per post in the thread.
  """
  def format_overview_line(thread_id, post_number, thread_title, thread_author \\ "Unknown") do
    article_num = generate_article_number(thread_id, post_number)
    message_id = generate_message_id(thread_id, article_num)
    
    # Format: article_num, subject, from, date, message-id, references, bytes, lines
    # We use placeholders for data we don't have at thread list level
    from = "#{thread_author}@forums.somethingawful.invalid"
    subject = thread_title
    date = format_rfc5322_date()
    references = ""
    bytes = "1024"  # Placeholder
    lines = "10"    # Placeholder
    
    "#{article_num}\t#{subject}\t#{from}\t#{date}\t#{message_id}\t#{references}\t#{bytes}\t#{lines}"
  end

  @doc """
  Formats current date/time in RFC 5322 format.
  Example: "Wed, 08 Jan 2026 05:00:00 +0000"
  """
  def format_rfc5322_date do
    now = DateTime.utc_now()
    Calendar.strftime(now, "%a, %d %b %Y %H:%M:%S +0000")
  end

  # Private helpers

  defp format_date(sa_date) do
    # SA date format: "Dec 25, 2024 at 10:30"
    # For now, return as-is
    # TODO: Convert to RFC 5322 format
    sa_date
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end
end
