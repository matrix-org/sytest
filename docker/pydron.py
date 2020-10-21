#!/venv/bin/python

import os
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


try:
    _print("Starting main process")

    # First, try and start Synapse (which will set up the database).
    synapse = (
        args["--synapse-python"]
        + " -m synapse.app.homeserver -D --config-path="
        + args["--synapse-config"]
    )
    subprocess.run(shlex.split(synapse), check=True)

    # Then, start up all the workers. Do these in parallel because they take a while.
    worker_processes = {}
    for i in configs.keys():
        # Get the synapse app name from the map, if needed. Otherwise, just
        # replace any dashes with underscores, so they match the Python module
        # name.
        appname = appname_map.get(i, i.replace("-", "_"))

        _print("Starting %s" % (appname,))

        base = (
            args["--synapse-python"]
            + " -m synapse.app."
            + appname
            + " -D --config-path="
            + args["--synapse-config"]
            + " --config-path="
            + configs[i]
        )
        worker_processes[appname] = subprocess.Popen(
            shlex.split(base),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    # wait for them all to daemonize (ie, for the parent process to exit)
    for appname, process in worker_processes.items():
        (output, _) = process.communicate()
        _print("-----\n%s output:" % appname)
        os.write(sys.stderr.fileno(), output)
        if process.returncode:
            raise Exception("%s failed to start" % (appname, ))

    # Nothing failed, let's say we've started and then signal we're up by
    # serving the webserver.
    _print("Synapse started!")

    class WebHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write("OK")
            return

    PORT_NUMBER = int(args["--addr"].split(":")[1])
    server = HTTPServer(('', PORT_NUMBER), WebHandler)
    server.serve_forever()

except KeyboardInterrupt:
   pass
except BaseException as e:
    # Log a traceback for debug
    import traceback
    traceback.print_exc()

    # If we get told to shut down, log it
    _print("Told to quit because %s" % (repr(e)))

    # Otherwise, something bad has happened.
    sys.exit(1)
finally:
   subprocess.run(["pkill", "-9", "-f", "synapse.app"])
