# Testing Guide

Manual testing guide for awful-nntp development.

## Prerequisites

### Set up credentials

```bash
cd ~/dev/awful-nntp
cp .env.example .env
# Edit .env with your SA username/password
```

## Quick Start

### Start the Server

```bash
cd ~/dev/awful-nntp
mix run --no-halt
```

You should see:
```
[info] NNTP server listening on port 1199
```

## Testing with Telnet

### Basic Connection Test

In a separate terminal:

```bash
telnet localhost 1199
```

**Expected response:**
```
Trying 127.0.0.1...
Connected to localhost.
200 awful-nntp ready (posting ok)
```

### Test CAPABILITIES Command

```
CAPABILITIES
```

**Expected response:**
```
101 Capability list
VERSION 2
READER
LIST ACTIVE
AUTHINFO USER
.
```

### Test LIST Command

**First, authenticate:**
```
AUTHINFO USER your_sa_username
```

**Expected response:**
```
381 Password required
```

```
AUTHINFO PASS your_sa_password
```

**Expected response:**
```
281 Authentication accepted
```

**Now list forums:**
```
LIST
```

**Expected response:**
```
215 Newsgroups follow
sa.general-bullshit 0 0 y
sa.games 0 0 y
sa.sports-argument 0 0 y
(... more forums ...)
.
```

**Note**: This fetches real SA forum data! It requires valid SA credentials.

### Test GROUP Command

```
GROUP sa.general-bullshit
```

**Expected response:**
```
211 0 0 0 sa.general-bullshit
```

**Invalid newsgroup:**
```
GROUP invalid
```

**Expected response:**
```
411 No such newsgroup
```

### Test AUTHINFO Commands

```
AUTHINFO USER your_sa_username
```

**Expected response:**
```
381 Password required
```

```
AUTHINFO PASS your_sa_password
```

**Expected response (with valid credentials):**
```
281 Authentication accepted
```

**Expected response (with invalid credentials):**
```
481 Authentication failed
```

### Test QUIT Command

```
QUIT
```

**Expected response:**
```
205 Closing connection
Connection closed by foreign host.
```

## Testing with NNTP Clients

### Install tin (Recommended)

```bash
sudo pacman -S tin
```

### Connect with tin

```bash
tin -r localhost:1199
```

**What to expect:**
- Connection banner
- Empty newsgroup list (no SA forums yet)
- Can test navigation and interface

### Install slrn (Alternative)

```bash
sudo pacman -S slrn
```

### Configure slrn

```bash
mkdir -p ~/.slrn
echo "server localhost 1199" > ~/.slrnrc
```

### Connect with slrn

```bash
slrn
```

## Expected Current Behavior

**What Works:**
- ✅ Server accepts connections
- ✅ Sends welcome banner
- ✅ Parses NNTP commands
- ✅ CAPABILITIES returns server capabilities
- ✅ AUTHINFO validates against real SA credentials
- ✅ LIST returns real SA forums (requires authentication)
- ✅ GROUP validates newsgroup names (stub data for now)
- ✅ QUIT closes connection cleanly

**What's In Progress:**
- ⏳ GROUP fetching thread lists (validates names but returns stub data)
- ⏳ ARTICLE retrieving posts (returns 430 - not implemented)

**What Doesn't Work Yet:**
- ❌ No thread listing in GROUP (returns 0 articles)
- ❌ No article retrieval (ARTICLE returns 430)
- ❌ No posting support (POST not implemented)
- ❌ No caching (every LIST hits SA)

## Automated Testing

Run the test suite:

```bash
mix test
```

**Expected output:**
```
........................
Finished in 0.1 seconds
1 doctest, 23 tests, 0 failures

All 24 tests passing ✅
```

Run specific test file:

```bash
mix test test/awful_nntp/nntp/protocol_test.exs
mix test test/awful_nntp/sa/parser_test.exs
```

## Fetching Sample Data

Fetch real SA HTML for testing/development:

```bash
cd ~/dev/awful-nntp
./scripts/fetch_sa_samples.exs
```

This creates:
- `samples/forums.html` - Main forum list
- `samples/forum_26.html` - Example forum (GBS)
- `samples/thread.html` - Example thread with posts

**Note**: Sample files are gitignored and not committed.

## Development Workflow

1. **Start server:**
   ```bash
   mix run --no-halt
   ```

2. **In another terminal, test with telnet:**
   ```bash
   telnet localhost 1199
   ```

3. **Make code changes**

4. **Stop server (Ctrl+C twice)**

5. **Restart and retest**

## Troubleshooting

### Port Already in Use

```bash
# Check what's using port 1199
ss -tlnp | grep 1199

# Kill the process
kill <PID>
```

### Server Won't Start

Check compilation errors:
```bash
mix compile
```

### Connection Refused

Ensure server is running:
```bash
ps aux | grep "mix run"
```

Check port is listening:
```bash
ss -tln | grep 1199
```

## Next Development Steps

After testing the current implementation, the next features to add are:

1. **GROUP Command** - Fetch thread lists from SA forums
2. **ARTICLE Command** - Fetch and format individual posts
3. **Caching Layer** - Cache forums/threads/posts to reduce SA load
4. **Posting Support** - Create threads and replies
5. **Error Handling** - Better handling of SA errors and edge cases
