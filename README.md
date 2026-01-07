# awful-nntp

Something Awful forums to NNTP bridge - Browse SA forums with your favorite NNTP client.

## Overview

`awful-nntp` is a protocol bridge that allows you to read and post to Something Awful forums using any NNTP (Network News Transfer Protocol) newsreader client. Connect with classic tools like `tin`, `slrn`, `Thunderbird`, or any other NNTP client.

## Features (Planned)

- Browse SA forum structure as newsgroups
- Read threads and posts via NNTP
- Post replies and new threads
- Stateless architecture with optional in-memory caching
- Portable: runs on ARM and x86 (32/64-bit) Linux systems

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

## Usage

```bash
# Start the NNTP server (default port 119)
mix run --no-halt

# Connect with your NNTP client
tin -r localhost
```

## License

MIT License - see [LICENSE](LICENSE) for details.

