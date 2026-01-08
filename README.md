# awful-nntp

Something Awful forums to NNTP bridge - Browse SA forums with your favorite NNTP client.

## Overview

`awful-nntp` is a protocol bridge that allows you to read and post to Something Awful forums using any NNTP (Network News Transfer Protocol) newsreader client. Connect with classic tools like `tin`, `slrn`, `Thunderbird`, or any other NNTP client.

## Status

**~60% Complete** - Core features working, article retrieval in progress

### Working Features ✅
- ✅ NNTP server on port 1199
- ✅ SA authentication with real credentials
- ✅ LIST command returns real SA forums
- ✅ HTML parsing (forums, threads, posts)
- ✅ SA to NNTP data mapping

### In Progress ⏳
- ⏳ GROUP command (fetch thread lists)
- ⏳ ARTICLE command (fetch individual posts)

### Planned Features ❌
- ❌ Posting support (create threads, reply to posts)
- ❌ Caching layer (reduce SA load)
- ❌ SSL/TLS support (NNTPS)

## Requirements

- Elixir 1.14+ / Erlang OTP 24+
- Something Awful forum account

## Installation

### Arch Linux

Install Erlang dependencies (Arch splits Erlang into separate packages):

```bash
sudo pacman -S elixir erlang-public_key erlang-ssl erlang-parsetools
```

### Debian/Ubuntu

```bash
sudo apt install elixir erlang
```

### Build from source

```bash
git clone https://github.com/sockbot/awful-nntp.git
cd awful-nntp
mix deps.get
mix compile
```

## Configuration

### Set up SA credentials

```bash
cp .env.example .env
# Edit .env and add your Something Awful username/password:
# SA_USERNAME=your_username
# SA_PASSWORD=your_password
```

**Security note**: The `.env` file is gitignored and credentials are never written to disk by the application.

## Usage

### Start the server

```bash
mix run --no-halt
# Server starts on port 1199
```

### Connect with an NNTP client

```bash
# Using tin
tin -r localhost:1199

# Or telnet for testing
telnet localhost 1199
```

### Authentication

Once connected, authenticate with your SA credentials:

```
AUTHINFO USER your_username
AUTHINFO PASS your_password
```

### Browse forums

```
LIST                     # List all SA forums
GROUP sa.general-bullshit  # Select a forum (not fully implemented yet)
```

## Testing

### Run automated tests

```bash
mix test
# All 24 tests passing ✅
```

### Fetch sample data (for development)

```bash
./scripts/fetch_sa_samples.exs
# Fetches real SA HTML to samples/ directory
```

## License

MIT License - see [LICENSE](LICENSE) for details.

