#!/bin/bash

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY

# PATH to the mesa-dockerfiles.git repository
MESA_DOCKER_FILES="${MESA_DOCKER_FILES:-$HOME/mesa-dockerfiles.git}"
# PATH where to place the piglit results
PIGLIT_RESULTS="${PIGLIT_RESULTS:-$HOME/i965/piglit-results}"

function cleanup {
    if [ "x${CONTAINER}" == "x" ]; then
	docker rm ${CONTAINER}
    fi

    exit $1
}

if [ -d "${MESA_DOCKER_FILES}" ]; then
    cd "${MESA_DOCKER_FILES}"
else
    cleanup 1
fi

git pull -q

dj -q -d Dockerfile.piglit.jinja -o Dockerfile -e RELEASE=17.0 -e MAKEFLAGS=-j2
CONTAINER=$(docker build -q --pull -f Dockerfile -t igalia/mesa:piglit .)
rm Dockerfile

if [ -d "${PIGLIT_RESULTS}" ]; then
    docker run --privileged --rm -t -v "${PIGLIT_RESULTS}":/results:Z  -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix igalia/mesa:piglit
else
    cleanup 2
fi

cleanup 0
