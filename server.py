import argparse
from nntpserver import NNTPConnectionHandler
from AwfulNNTPServer import AwfulNNTPServer

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SomethingAwful NNTP server")
    parser.add_argument("--port", type=int, default=1199)
    parser.add_argument("--host", type=str, default="localhost")
    args = parser.parse_args()

    with AwfulNNTPServer(
        (args.host, args.port), NNTPConnectionHandler
    ) as server:
        print(f"Listening on {args.host}:{args.port}")
        server.allow_reuse_address = True
        # Activate the server; this will keep running until you
        # interrupt the program with Ctrl-C
        server_thread = threading.Thread(target=server.serve_forever)
        server_thread.daemon = True
        server_thread.start()
        try:
            server_thread.join()
        except KeyboardInterrupt:
            pass
        finally:
            server.shutdown()
