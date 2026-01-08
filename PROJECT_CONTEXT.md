# Project Context: awful-nntp

**Last Updated**: January 7, 2025
**Status**: Active development - Core features working, ~60% complete

## 1. Project Overview

`awful-nntp` is a protocol bridge that translates between NNTP (Network News Transfer Protocol) and Something Awful's web forums. It allows users to browse and interact with SA forums using any NNTP newsreader client (tin, slrn, Thunderbird, etc.).

### Current State
- **TCP server**: ✅ Running on port 1199
- **NNTP protocol parser**: ✅ Implemented and tested
- **SA authentication**: ✅ Working (login flow complete)
- **SA HTML parser**: ✅ Complete (forums, threads, posts)
- **Connection handling**: ✅ GenServer per connection
- **Forum fetching**: ✅ LIST command returns real SA forums
- **Mapping layer**: ✅ Converts SA data to NNTP format
- **Article retrieval**: ⏳ In progress (GROUP next)
- **Posting**: ❌ Not yet implemented

The server can authenticate with SA, fetch real forum data, and return it via NNTP LIST command. Next phase is implementing GROUP and ARTICLE commands.

## 2. Architecture Summary

### High-Level Flow
```
NNTP Client (tin/slrn) <--NNTP--> awful-nntp <--HTTP--> SA Forums (web scraping)
```

### Key Components

**TCP Server** (`lib/awful_nntp/nntp/server.ex`)
- Listens on port 1199
- Spawns Connection GenServer for each client
- Supervised by DynamicSupervisor

**Connection Handler** (`lib/awful_nntp/nntp/connection.ex`)
- One GenServer per NNTP client
- Maintains connection state (authenticated, current_group, sa_client)
- Processes commands and sends responses

**Protocol Parser** (`lib/awful_nntp/nntp/protocol.ex`)
- Parses NNTP commands (RFC 3977)
- Formats NNTP responses
- Validates newsgroup names

**SA Client** (`lib/awful_nntp/sa/client.ex`)
- HTTP client using Req library
- Handles SA authentication (cookies)
- Fetches forum/thread pages

**SA Parser** (`lib/awful_nntp/sa/parser.ex`)
- HTML parser using Floki
- Extracts forums from main page
- Extracts threads from forum pages
- Extracts posts from thread pages

**Mapping Layer** (`lib/awful_nntp/mapping.ex`)
- Converts SA forums to NNTP newsgroups
- Converts SA threads to NNTP article lists
- Formats SA posts as NNTP articles with headers

### Supervisor Tree
```
AwfulNntp.Application (Supervisor)
├── DynamicSupervisor (ConnectionSupervisor)
│   └── AwfulNntp.NNTP.Connection (one per client)
└── AwfulNntp.NNTP.Server (TCP listener)
```

### Data Mapping

**Forums → Newsgroups**
```
SA: "General Bullshit"  →  NNTP: sa.general-bullshit
SA: "Games"             →  NNTP: sa.games
```

**Threads → Articles**
```
Article Number: <thread_id><post_id>
Message-ID: <post_id.thread_id@forums.somethingawful.com>
Subject: Thread title
From: username@somethingawful.com
```

## 3. What's Been Built

### Completed Features

**NNTP Server** (`lib/awful_nntp/nntp/server.ex`)
- TCP listener on configurable port
- Connection acceptance loop
- Client handoff to Connection GenServer

**Protocol Parser** (`lib/awful_nntp/nntp/protocol.ex`)
- Command parsing: CAPABILITIES, QUIT, LIST, GROUP, ARTICLE, AUTHINFO, etc.
- Response formatting (single and multi-line)
- Newsgroup name validation (sa.* pattern)
- Full test coverage

**Connection Handler** (`lib/awful_nntp/nntp/connection.ex`)
- Command dispatch
- State management (authenticated, current_group)
- Implements: CAPABILITIES, QUIT, LIST (empty), GROUP (stub), AUTHINFO

**SA Authentication** (`lib/awful_nntp/sa/client.ex`)
- Login via POST to account.php
- Cookie extraction and management
- Authenticated Req client creation
- Forum/thread fetch functions (ready to use)

**Application Supervision** (`lib/awful_nntp/application.ex`)
- OTP Application setup
- Supervisor tree with DynamicSupervisor for connections
- Configurable port

### File Structure
```
lib/awful_nntp/
├── application.ex              # OTP Application & supervision
├── nntp/
│   ├── server.ex              # TCP server (complete)
│   ├── connection.ex          # Connection handler (complete)
│   └── protocol.ex            # Protocol parser (complete)
├── sa/
│   ├── client.ex              # HTTP client (complete)
│   └── parser.ex              # HTML parser (complete)
└── mapping.ex                  # SA to NNTP data conversion (complete)
```

## 4. Current State

### What Works ✅

1. **Server startup**: `mix run --no-halt` starts TCP server
2. **Client connections**: Clients can connect via telnet/tin/slrn
3. **Welcome banner**: Sends `200 awful-nntp ready (posting ok)`
4. **CAPABILITIES**: Returns server capabilities list
5. **QUIT**: Closes connection gracefully
6. **AUTHINFO USER/PASS**: Authenticates with SA, stores authenticated client
7. **SA authentication**: Successfully logs into SA and gets cookies
8. **LIST command**: Returns real SA forums from authenticated session
9. **SA HTML parsing**: Parses forums, threads, and posts from HTML
10. **Mapping layer**: Converts SA data to NNTP format

### What's In Progress ⏳

1. **GROUP command**: Needs to fetch thread list for selected forum
2. **ARTICLE command**: Needs to fetch and format individual posts

### What Doesn't Work Yet ❌

1. **Thread listing**: GROUP returns stub data (needs thread fetching)
2. **Article retrieval**: ARTICLE returns 430 (needs post fetching)
3. **Posting**: POST not implemented
4. **Caching**: No caching layer yet (every LIST fetches fresh data)

### Test Status

**24 tests total, all passing ✅**
- Protocol tests: ✅ All passing (9 tests)
- Connection tests: ✅ All passing (5 tests)
- SA Client tests: ✅ All passing (3 tests)
- SA Parser tests: ✅ All passing (6 tests)
- Mapping tests: ✅ All passing (1 doctest)

Run tests: `mix test`

## 5. Next Steps

### Immediate Priorities (in order)

1. **Implement GROUP command** ✅ Started
   - Fetch thread list for selected forum
   - Parse thread HTML with SA.Parser
   - Map threads to article numbers
   - Return article range and count

2. **Implement ARTICLE/HEAD/BODY commands**
   - Parse article numbers (thread_id * 1000000 + post_num)
   - Fetch and parse thread HTML
   - Format posts as NNTP articles with headers
   - Use Mapping module for formatting

3. **Add caching layer**
   - Create Cache GenServer with ETS table
   - Cache forums (15 min TTL)
   - Cache threads (5 min TTL)
   - Cache posts (30 min TTL)
   - Reduces SA load and improves performance

4. **Implement posting**
   - POST command handler
   - Submit replies to SA via HTTP POST
   - Handle SA's CSRF tokens
   - Support thread creation and replies

5. **Error handling and edge cases**
   - Handle SA errors (banned, thread deleted, etc.)
   - Rate limiting on SA requests
   - Handle locked/archived threads
   - Better error messages to client

### Lower Priority
- SSL/TLS support (NNTPS on port 563)
- XOVER command for better client support
- Search functionality
- Persistent cache (Redis/SQLite)
- Metrics/telemetry

## 6. Key Decisions

### Technical Choices

**Language**: Elixir/OTP
- Excellent concurrency model (one GenServer per connection)
- Robust supervision for fault tolerance
- Pattern matching ideal for protocol parsing

**HTTP Client**: Req (with Finch backend)
- Modern Elixir HTTP client
- Built-in cookie handling
- Connection pooling

**HTML Parsing**: Floki
- Standard Elixir HTML parser
- CSS selector support
- Already in dependencies

**No Database**: Stateless design
- In-memory caching only (ETS)
- No persistent storage of SA content
- Simpler deployment

**Port 1199**: Non-standard NNTP port
- Avoids requiring root (standard port 119)
- Easy to change via config

**Article Numbering**: `thread_id * 1000000 + post_num`
- Ensures unique sequential numbers
- Easy to parse back to thread/post
- Supports up to 999,999 posts per thread

### Protocol Decisions

**Minimal NNTP**: Implement only required commands
- Focus on reading (LIST, GROUP, ARTICLE)
- Posting secondary priority
- No advanced features (search, XOVER)

**Authentication**: Use SA credentials directly
- AUTHINFO USER/PASS takes SA username/password
- No separate NNTP authentication layer
- One authenticated client per connection

## 7. Development Workflow

### Starting the Server
```bash
cd ~/dev/awful-nntp
mix run --no-halt
# Server starts on port 1199
```

### Manual Testing with Telnet
```bash
telnet localhost 1199
# Try: CAPABILITIES, LIST, GROUP sa.test, QUIT
```

### Testing with Real Client
```bash
tin -r localhost:1199
```

### Running Tests
```bash
mix test                    # All tests
mix test test/awful_nntp/nntp/protocol_test.exs  # Specific file
mix test --trace           # Verbose output
```

### Code Formatting
```bash
mix format
```

### Recompiling After Changes
The server automatically recompiles on restart, but you can manually compile:
```bash
mix compile
```

## 8. File Structure Quick Reference

### Core Application
- `lib/awful_nntp.ex` - Main module
- `lib/awful_nntp/application.ex` - OTP Application & supervision
- `mix.exs` - Project configuration & dependencies
- `config/config.exs` - Runtime configuration

### NNTP Implementation
- `lib/awful_nntp/nntp/server.ex` - TCP server
- `lib/awful_nntp/nntp/connection.ex` - Connection handler
- `lib/awful_nntp/nntp/protocol.ex` - Protocol parser/formatter

### SA Integration
- `lib/awful_nntp/sa/client.ex` - HTTP client & auth ✅
- `lib/awful_nntp/sa/parser.ex` - HTML parsing ✅

### Mapping Layer
- `lib/awful_nntp/mapping.ex` - SA to NNTP conversion ✅

### Tests
- `test/awful_nntp/nntp/protocol_test.exs` - Protocol tests ✅
- `test/awful_nntp/nntp/connection_test.exs` - Connection tests ✅
- `test/awful_nntp/sa/client_test.exs` - SA client tests ✅
- `test/awful_nntp/sa/parser_test.exs` - Parser tests ✅

### Scripts
- `scripts/fetch_sa_samples.exs` - Fetch real SA HTML for testing

### Documentation
- `README.md` - Project overview
- `ARCHITECTURE.md` - Detailed architecture docs
- `TESTING.md` - Manual testing guide
- `PROJECT_CONTEXT.md` - This file

## 9. Dependencies

### Production Dependencies

**req** (~> 0.4.0)
- Modern HTTP client for Elixir
- Used for SA forum requests
- Includes Finch (HTTP/1.1 and HTTP/2) and Mint
- Handles cookies, redirects, connection pooling

**floki** (~> 0.35.0)
- HTML parser and CSS selector engine
- Used to scrape SA forum pages
- Parses forum lists, threads, posts

### Test Dependencies

**bypass** (~> 2.1)
- Creates mock HTTP servers for testing
- Used to test SA.Client without real SA requests

**mox** (~> 1.1)
- Mock library for Elixir
- Used for testing with mock behaviors

### Standard Library
- `:gen_tcp` - TCP socket handling
- `:logger` - Logging
- `:crypto` - Available if needed for hashing

## 10. Authentication Setup

### Environment Variables

The project uses `.env` file for SA credentials (not committed to git).

**Setup**:
```bash
cd ~/dev/awful-nntp
cp .env.example .env
# Edit .env with your SA username/password
```

**.env format**:
```bash
SA_USERNAME=your_username_here
SA_PASSWORD=your_password_here
```

**.env.example** (tracked in git):
Template file with placeholder values.

**Security**:
- `.env` is in `.gitignore`
- Credentials never written to disk by the application
- Each connection stores its own authenticated client in memory
- Credentials are cleared when connection closes

### How Auth Works (✅ Implemented)

1. Client sends `AUTHINFO USER <username>`
2. Server responds `381 Password required`
3. Client sends `AUTHINFO PASS <password>`
4. Server calls `SA.Client.authenticate(username, password)`
5. SA.Client POSTs to SA login page, extracts cookies
6. Returns authenticated Req client (or error)
7. Connection stores authenticated client in state
8. Future requests (LIST, GROUP, etc.) use this client to fetch SA content

### Fetching Sample HTML Files

A script is provided to fetch real SA HTML for testing/development:

```bash
cd ~/dev/awful-nntp
./scripts/fetch_sa_samples.exs
```

This fetches:
- `samples/forums.html` - Main forum list
- `samples/forum_26.html` - Example forum (GBS)
- `samples/thread.html` - Example thread with posts

Samples are in `.gitignore` and not committed to avoid copyright issues.

---

## Quick Start for New Developer

1. **Clone and setup**:
   ```bash
   cd ~/dev/awful-nntp
   mix deps.get
   cp .env.example .env
   # Add your SA credentials to .env
   ```

2. **Run tests**:
   ```bash
   mix test
   # All 24 tests passing ✅
   ```

3. **Start server**:
   ```bash
   mix run --no-halt
   ```

4. **Test connection**:
   ```bash
   telnet localhost 1199
   CAPABILITIES
   QUIT
   ```

5. **Fetch sample data** (optional):
   ```bash
   ./scripts/fetch_sa_samples.exs
   # Fetches real SA HTML for testing
   ```

6. **Next task**: Implement GROUP command to fetch thread lists

---

## Questions to Answer Before Resuming

- Which SA forums should be supported initially?
- How should we handle SA's rate limiting?
- Should we support viewing locked/archived threads?
- How to handle SA's image attachments in posts?
- Should we parse BBCode or convert to plain text?

## Known Issues

1. No caching (every LIST command hits SA)
2. No rate limiting on SA requests
3. No handling of SA errors (banned, thread deleted, etc.)
4. GROUP command not fully implemented yet
5. ARTICLE command not implemented yet

## Resources

- **NNTP RFC**: RFC 3977 (https://tools.ietf.org/html/rfc3977)
- **SA Forums**: https://forums.somethingawful.com
- **Req docs**: https://hexdocs.pm/req
- **Floki docs**: https://hexdocs.pm/floki
- **OTP docs**: https://www.erlang.org/doc/design_principles/users_guide.html
