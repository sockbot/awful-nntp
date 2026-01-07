# Architecture Documentation

## Overview

`awful-nntp` is a stateless protocol bridge that translates between NNTP (Network News Transfer Protocol) and Something Awful's web forums. It allows users to browse and interact with SA forums using any NNTP newsreader client.

## High-Level Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  NNTP Client    │◄───────►│  awful-nntp      │◄───────►│ SA Forums       │
│  (tin/slrn/     │  NNTP   │  Bridge Server   │  HTTP   │ (Web Scraping)  │
│   Thunderbird)  │         │                  │         │                 │
└─────────────────┘         └──────────────────┘         └─────────────────┘
```

## NNTP Protocol Implementation

### Required NNTP Commands

We need to implement a minimal subset of RFC 3977 (NNTP):

**Connection & Authentication:**
- `CAPABILITIES` - List server capabilities
- `AUTHINFO USER/PASS` - Authenticate with SA credentials
- `QUIT` - Close connection

**Newsgroup Operations:**
- `LIST` - List available newsgroups (SA forums)
- `GROUP` - Select a newsgroup (SA forum)
- `LISTGROUP` - List article numbers in current group

**Article Retrieval:**
- `ARTICLE` - Retrieve full article (SA post)
- `HEAD` - Retrieve article headers only
- `BODY` - Retrieve article body only
- `STAT` - Check if article exists

**Posting (Future):**
- `POST` - Submit new article (SA post/thread)

### Response Codes
- `200` - Service available
- `215` - Newsgroup list follows
- `220` - Article headers follow
- `221` - Article body follows
- `223` - Article exists
- `381` - Password required
- `411` - No such newsgroup
- `430` - No such article
- `500` - Command not understood

## SA Forums → NNTP Mapping

### Forums → Newsgroups

SA forum structure maps to NNTP newsgroups:

```
SA Forums                    NNTP Newsgroup Name
─────────────────────────   ─────────────────────────
General Bullshit         →  sa.general-bullshit
Games                    →  sa.games
Ask/Tell                 →  sa.ask-tell
Sports Argument Stadium  →  sa.sports-argument-stadium
```

**Newsgroup naming convention:**
- Prefix: `sa.`
- Forum name: lowercase, spaces → hyphens
- Example: "Debate & Discussion" → `sa.debate-discussion`

### Threads → Articles

SA thread/post structure maps to NNTP articles:

```
Article Number:  <thread_id><post_id> (e.g., 4123456001 = thread 4123456, post 1)
Message-ID:      <post_id.thread_id@forums.somethingawful.com>
Subject:         Thread title
From:            username@somethingawful.com
Date:            Post timestamp (RFC 5322 format)
Newsgroups:      sa.forum-name
References:      Thread hierarchy for replies
```

**Article numbering scheme:**
- Thread ID × 1000000 + Post Number
- Ensures unique, sequential article numbers per forum
- Example: Thread 1234567, Post 5 → Article number 1234567005

## Module Structure

```
lib/awful_nntp/
├── application.ex              # OTP Application & Supervisor
├── nntp/
│   ├── server.ex              # TCP server (accepts connections)
│   ├── connection.ex          # GenServer per NNTP connection
│   ├── protocol.ex            # NNTP protocol parser/formatter
│   └── commands.ex            # NNTP command handlers
├── sa/
│   ├── client.ex              # HTTP client for SA forums
│   ├── parser.ex              # HTML parsing (Floki)
│   ├── forums.ex              # Forum listing/structure
│   ├── threads.ex             # Thread listing
│   └── posts.ex               # Post retrieval/parsing
├── cache.ex                   # In-memory cache (ETS)
└── mapping.ex                 # SA ↔ NNTP translation logic
```

## Supervisor Tree

```
AwfulNntp.Application (Supervisor)
├── AwfulNntp.Cache (GenServer - ETS table owner)
├── AwfulNntp.NNTP.Server (Task - TCP listener)
└── DynamicSupervisor (for connection handlers)
    ├── AwfulNntp.NNTP.Connection (GenServer)
    ├── AwfulNntp.NNTP.Connection (GenServer)
    └── ... (one per NNTP client connection)
```

**Supervision strategy:**
- Application supervisor: `:one_for_one`
- Connection supervisor: `:temporary` (connections can fail independently)
- Cache survives connection failures

## Data Flow

### Reading a Thread

1. Client sends: `GROUP sa.general-bullshit`
2. Connection → SA.Client: Fetch forum page
3. SA.Parser: Extract thread list
4. Cache: Store threads (5 min TTL)
5. Connection → Client: `211 450 1 500 sa.general-bullshit`

6. Client sends: `ARTICLE 4123456001`
7. Connection: Check cache for post
8. If miss: SA.Client → fetch post
9. SA.Parser: Extract post content
10. Mapping: Convert to NNTP format
11. Connection → Client: NNTP-formatted article

### Caching Strategy

**In-memory cache (ETS) with TTL:**
- Forum list: 15 minutes
- Thread list per forum: 5 minutes
- Individual posts: 30 minutes
- No persistence (stateless)

**Cache keys:**
```elixir
{:forum_list}
{:threads, forum_id}
{:post, thread_id, post_number}
```

## Concurrency Model

- **One GenServer per NNTP connection** - Isolated state, independent failures
- **Shared ETS cache** - Concurrent reads, serialized writes
- **HTTP requests via Req** - Connection pooling via Finch
- **Rate limiting** - Limit concurrent SA requests to avoid bans

## Configuration

Configuration via environment variables:

```bash
NNTP_PORT=119              # NNTP server port
NNTP_HOST=0.0.0.0          # Bind address
SA_BASE_URL=https://forums.somethingawful.com
CACHE_TTL_FORUMS=900       # 15 minutes
CACHE_TTL_THREADS=300      # 5 minutes
CACHE_TTL_POSTS=1800       # 30 minutes
MAX_CONNECTIONS=100        # Max concurrent NNTP clients
```

## Security Considerations

1. **SA Authentication:** Store credentials per connection (not server-wide)
2. **Rate Limiting:** Avoid hammering SA servers
3. **Input Validation:** Sanitize all NNTP commands
4. **No Persistence:** Credentials never written to disk

## Future Enhancements

1. **Posting Support:** Implement `POST` command to create threads/replies
2. **Search:** Map NNTP `XHDR` to SA search
3. **Subscriptions:** Remember user's subscribed forums
4. **SSL/TLS:** Support NNTPS (port 563)
5. **Persistent Cache:** Optional Redis/SQLite backend
6. **Metrics:** Telemetry for monitoring

## Testing Strategy

1. **Unit tests:** Protocol parsing, SA HTML parsing
2. **Integration tests:** Mock SA responses
3. **Property tests:** NNTP protocol compliance
4. **Manual testing:** Real NNTP clients (tin, slrn)

## Performance Targets

- Handle 100 concurrent NNTP connections
- Sub-second response for cached content
- < 2 second response for uncached SA requests
- Memory footprint < 50MB (excluding cache)
