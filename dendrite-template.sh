# Respective volumes:
# 1. cloned https://github.com/matrix-org/sytest repo location
# 2. cloned https://github.com/matrix-org/dendrite repo locatopn
# 3. directory for tests logs
# 4. used not to download packages each time
# 5. build cache, speeds up binaries build
# Envs:
# for env configuration, refer to https://github.com/matrix-org/dendrite/blob/master/docs/sytest.md
# Args:
# choosing test to run as last argument

docker run --rm \
-v "/Users/piotrkozimor/repos/sytest:/sytest" \
-v "/Users/piotrkozimor/repos/dendrite:/src" \
-v "/Users/piotrkozimor/logs:/logs" \
-v "/Users/piotrkozimor/go/:/gopath" \
-v "/Users/piotrkozimor/go-build/:/go-build" \
-e "POSTGRES=1" -e "DENDRITE_TRACE_HTTP=1" \
matrixdotorg/sytest-dendrite:latest tests/11register.pl