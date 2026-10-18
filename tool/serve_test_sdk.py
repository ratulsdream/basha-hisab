"""Serve the public test SDK bundle on loopback with module CORS headers."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True)
    parser.add_argument('--port', type=int, default=9030)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port), partial(Handler, directory=args.directory)).serve_forever()
