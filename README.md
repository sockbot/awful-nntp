# awful-nntp

Something Awful forums to NNTP bridge - Browse SA forums with your favorite NNTP client.

## Overview

`awful-nntp` is a protocol bridge that allows you to read and post to Something Awful forums using any NNTP (Network News Transfer Protocol) newsreader client. Connect with classic tools like `tin`, `slrn`, `Thunderbird`, or any other NNTP client.

## Installation into virtual env

```
uv venv
source .venv/bin/activate
uv pip install -r requirements.txt
```

## Usage

### Start server

```
# start server at localhost:1199
python server.py
```

### Start client

```
# example using tin
tin -r localhost:1199
```

## License

MIT
