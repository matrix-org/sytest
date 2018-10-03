#!/venv/bin/python

import shlex, subprocess
import sys
from six.moves.BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer

import time
import requests


def _print(out):
    sys.stderr.write(str(out) + "\n")
    sys.stderr.flush()


_print("Starting pydron...")

input_args = sys.argv[1:]

args = {}

while input_args:
    key = input_args.pop(0)
    args[key] = input_args.pop(0)

configs = {}
urls = {}

for x in args.keys():
    if x != "--synapse-config" and x.endswith("-config"):
        configs[x[2 : -len("-config")]] = args[x]

    if x.endswith("-url"):
        urls[x[2 : -len("-url")]] = args[x]

appname_map = {"user-directory": "user_dir"}


def wait_for_start(process, url):

    tries = 10
    while tries != 0:
        tries -= 1

        try:
            r = requests.get("http://" + url.replace("http://", ""), timeout=5)
            if r.status_code:
                return
        except Exception as e:
            time.sleep(2)
            pass

    process.terminate()
    raise ValueError("Never started, couldn't get %s!" % (url,))


running = {}

try:
    synapse = (
        args["--synapse-python"]
        + " -m synapse.app.homeserver --config-path="
        + args["--synapse-config"]
    )
    # _print("Calling %s" % (synapse,))
    syn = subprocess.Popen(
        shlex.split(synapse), stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )

    running["synapse"] = syn
    wait_for_start(syn, urls["synapse"])

    for i in configs.keys():

        appname = appname_map.get(i, i.replace("-", "_"))

        base = (
            args["--synapse-python"]
            + " -m synapse.app."
            + appname
            + " --config-path="
            + configs[i]
            + " --config-path="
            + args["--synapse-config"]
        )
        # _print("Calling %s" % (base,))
        exc = subprocess.Popen(
            shlex.split(base), stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        running[i] = exc

    # Give them some time to start up...
    time.sleep(3)

    # Check if any have outright failed to start up (syntax errors, etc)
    failed_units = []

    for x in running.keys():
        if x in urls:
            wait_for_start(running[x], urls[x])

        code = running[x].poll()

        if code:
            _print("%s exited uncleanly with %s!" % (x, code))
            failed_units.append(x)

    if failed_units:
        raise ValueError("failed units: %r" % (failed_units,))

    # Nothing failed, let's say we've started and then signal we're up by
    # serving the webserver.
    print("Synapse started!")

    class WebHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write("OK")
            return

    PORT_NUMBER = int(args["--addr"].split(":")[1])
    server = HTTPServer(('', PORT_NUMBER), WebHandler)
    server.serve_forever()

except BaseException as e:
    _print("Told to quit because %s" % (repr(e)))

    for x in running.keys():
        if not running[x].returncode:
            _print("Terminating %s" % (x,))
            running[x].terminate()
        else:
            _print("%s was already dead" % (x,))

    # If it's keyboard interrupt, exit cleanly.
    if isinstance(e, KeyboardInterrupt):
        sys.exit(0)

    # Otherwise, something bad has happened.
    sys.exit(1)
