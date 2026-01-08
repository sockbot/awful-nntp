# Testing Guide

Manual testing guide for awful-nntp development.

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

```
LIST
```

**Expected response:**
```
215 Newsgroups follow
.
```

(Empty for now - no SA forums configured yet)

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
AUTHINFO USER testuser
```

**Expected response:**
```
381 Password required
```

```
AUTHINFO PASS testpass
```

**Expected response:**
```
281 Authentication accepted
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
- ✅ LIST returns empty (no forums yet)
- ✅ GROUP validates newsgroup names
- ✅ AUTHINFO accepts credentials (no validation yet)
- ✅ QUIT closes connection cleanly

**What Doesn't Work Yet:**
- ❌ No actual SA forum data (LIST returns empty)
- ❌ No articles to retrieve (ARTICLE returns 430)
- ❌ No real authentication (all credentials accepted)
- ❌ No posting support

## Automated Testing

Run the test suite:

```bash
mix test
```

**Expected output:**
```
21/23 tests passing
2 failures (SA parser tests - not implemented yet)
```

Run specific test file:

```bash
mix test test/awful_nntp/nntp/protocol_test.exs
```

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

1. **SA Forum Scraping** - Fetch real forum data
2. **Forum List Caching** - Cache forum structure
3. **Article Retrieval** - Fetch and format posts
4. **Authentication** - Real SA login integration
5. **Posting Support** - Create threads and replies
