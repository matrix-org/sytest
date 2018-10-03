#!/venv/bin/python

import shlex
import subprocess
import sys
import time

import requests
from six.moves.BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer


def _print(out):
    """
    Print to stderr, so it shows up in the sytest logs when TAP is being used.
    """
    sys.stderr.write(str(out) + "\n")
    sys.stderr.flush()


def wait_for_start(process, url):
    """
    Wait for the start of Synapse by polling its HTTP endpoint.
    """
    tries = 10
    while tries != 0:
        tries -= 1

        try:
            r = requests.get("http://" + url, timeout=5)
            if r.status_code:
                # We don't care what the status code is, just that it's
                # responding.
                return
        except Exception as e:
            time.sleep(2)
            pass

    process.terminate()
    raise ValueError("Never started, couldn't get %s!" % (url,))


_print("Starting pydron...")

# Sort the args into key:value pairs in a dict
input_args = sys.argv[1:]
args = {}

while input_args:
    key = input_args.pop(0)
    args[key] = input_args.pop(0)

# Using the key:value arg pairs, parse which ones are config paths.
configs = {}

for x in args.keys():
    if x != "--synapse-config" and x.endswith("-config"):
        # Strip the first two dashes and -config off it
        configs[x[2 : -len("-config")]] = args[x]

# One of the config options is named differently than the actual app script, so,
# create a map for it.
appname_map = {"user-directory": "user_dir"}

# running is where we'll keep a map of app name to the Popen object (so we can
# terminate it later).
running = {}

try:
    # First, try and start Synapse (which will set up the database).
    synapse = (
        args["--synapse-python"]
        + " -m synapse.app.homeserver --config-path="
        + args["--synapse-config"]
    )
    syn = subprocess.Popen(
        shlex.split(synapse), stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    running["synapse"] = syn

    # Wait for Synapse to start by polling its webserver until it responds.
    wait_for_start(syn, args["--synapse-url"])

    # Then, start up all the workers.
    for i in configs.keys():

        # Get the synapse app name from the map, if needed. Otherwise, just
        # replace any dashes with underscores, so they match the Python module
        # name.
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
    # If we get told to shut down, log it
    _print("Told to quit because %s" % (repr(e)))

    # Terminate all the workers as cleanly as possible.
    for x in running.keys():
        if not running[x].returncode:
            _print("Terminating %s" % (x,))
            running[x].terminate()
        else:
            _print("%s was already dead" % (x,))

    # If it's keyboard interrupt, exit cleanly -- sytest is finished.
    if isinstance(e, KeyboardInterrupt):
        sys.exit(0)

    # Otherwise, something bad has happened.
    sys.exit(1)
