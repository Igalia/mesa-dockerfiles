#!/bin/bash

# Paths
# -----

# PATH to the mesa-dockerfiles.git repository
CDP_MESA_DOCKERFILES_DIR="${CDP_MESA_DOCKERFILES_DIR:-$HOME/mesa-dockerfiles.git}"
# PATH where to place the piglit results
CDP_PIGLIT_RESULTS_DIR="${CDP_PIGLIT_RESULTS_DIR:-$HOME/i965/piglit-results}"
# PATH where for ccache's directory
CDP_DOCKER_CCACHE_DIR="${CDP_DOCKER_CCACHE_DIR:-$HOME/i965/piglit-results/docker-ccache}"

# Verbose?
# --------

CDP_VERBOSE="${CDP_VERBOSE:-false}"

usage()
{
    echo -e "\e[31mUSAGE:"
    echo -e "\e[31m$0 <release>"
}

if ! [ $1 ]; then
    usage
    exit -1
fi

RELEASE="${1}"
shift

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY

if ${CDP_VERBOSE}; then
    CDP_OUTPUT=1
    CDP_QUIET=""
else
    CDP_OUTPUT=/dev/null
    CDP_QUIET="-q"
fi

function cleanup {
    if [ "x$1" == "x0" ]; then
        docker rmi image-piglit >&"${CDP_OUTPUT}" 2>&1
    fi

    exit $1
}

if [ -d "${CDP_MESA_DOCKERFILES_DIR}" ]; then
    cd "${CDP_MESA_DOCKERFILES_DIR}"
else
    echo "${CDP_MESA_DOCKERFILES_DIR} directory doesn't exist."
    cleanup 1
fi

if [ ! -d "${CDP_PIGLIT_RESULTS_DIR}" ]; then
    echo "${CDP_PIGLIT_RESULTS_DIR} directory doesn't exist."
    cleanup 2
fi

if [ ! -d "${CDP_DOCKER_CCACHE_DIR}" ]; then
    echo "${CDP_DOCKER_CCACHE_DIR} directory doesn't exist."
    cleanup 3
fi

git pull ${CDP_QUIET}

dj ${CDP_QUIET} -d Dockerfile.piglit.jinja -o Dockerfile -e RELEASE="${RELEASE}" -e MAKEFLAGS=-j2
docker build ${CDP_QUIET} --pull -f Dockerfile -t image-piglit .
rm Dockerfile
docker run -v "${CDP_DOCKER_CCACHE_DIR}":/home/local/.ccache \
       -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
       --name container-piglit image-piglit \
       "/bin/sh" "-c" "cmake . && make" >&"${CDP_OUTPUT}" 2>&1
docker commit container-piglit image-piglit >&"${CDP_OUTPUT}" 2>&1
docker rm container-piglit >&"${CDP_OUTPUT}" 2>&1

if [ -d "${CDP_PIGLIT_RESULTS_DIR}" ]; then
    for i in i965 llvmpipe swr softpipe; do
	docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
	       -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
	       -e FPR_VERBOSE=$CDP_VERBOSE \
	       -e GL_DRIVER=$i image-piglit \
	       "/bin/sh" "-c" "cat /home/local/mesa-head.txt >> /results/mesa-head.txt && cat /home/local/piglit-head.txt >> /results/piglit-head.txt && export MESA_COMMIT=\$(grep commit /home/local/mesa-head.txt | cut -d \" \" -f 2) && export FPR_CREATE_PIGLIT_REPORT=true && export FPR_RUN_PIGLIT=true && export FPR_PIGLIT_PATH=/home/local/piglit && export FPR_PIGLIT_REPORTS_PATH=/results && /home/local/full-piglit-run.sh \$GL_DRIVER \$MESA_COMMIT"
    done
else
    cleanup 2
fi

cleanup 0
