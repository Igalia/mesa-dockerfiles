#!/bin/bash

export LC_ALL=C

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY


#------------------------------------------------------------------------------
#			Function: backup_redirection
#------------------------------------------------------------------------------
#
# backups current stout and sterr file handlers
function backup_redirection() {
        exec 7>&1            # Backup stout.
        exec 8>&2            # Backup sterr.
        exec 9>&1            # New handler for stout when we actually want it.
}


#------------------------------------------------------------------------------
#			Function: restore_redirection
#------------------------------------------------------------------------------
#
# restores previously backed up stout and sterr file handlers
function restore_redirection() {
        exec 1>&7 7>&-       # Restore stout.
        exec 2>&8 8>&-       # Restore sterr.
        exec 9>&-            # Closing open handler.
}


#------------------------------------------------------------------------------
#			Function: check_verbosity
#------------------------------------------------------------------------------
#
# perform sanity check on the passed verbosity level:
#   $1 - the verbosity to use
# returns:
#   0 is success, an error code otherwise
function check_verbosity() {
    case "x$1" in
	"xfull" | "xnormal" | "xquiet" )
	    ;;
	*)
	    printf "%s\n" "Error: Only verbosity levels among [full|normal|quiet] are allowed." >&2
	    usage
	    return 1
	    ;;
    esac

    return 0
}


#------------------------------------------------------------------------------
#			Function: apply_verbosity
#------------------------------------------------------------------------------
#
# applies the passed verbosity level to the output:
#   $1 - the verbosity to use
function apply_verbosity() {

    backup_redirection

    if [ "x$1" != "xfull" ]; then
	exec 1>/dev/null
	RCR_PROGRESS_FLAG="-q"
    fi

    if [ "x$1" == "xquiet" ]; then
	exec 2>/dev/null
	exec 9>/dev/null
    fi
}

# Verbosity level
# ---------------

RCR_VERBOSITY="${RCR_VERBOSITY:-normal}"

check_verbosity "$RCR_VERBOSITY"
if [ $? -ne 0 ]; then
    exit 13
fi

apply_verbosity "$RCR_VERBOSITY"

# ---


RCR_DOCKER_REPOSITORY="baltix.local.igalia.com:5000/mesa"

RCR_DOCKER_RUN_COMMAND="TIMESTAMP=`date +%Y%m%d%H%M%S`;"

if [ x$2 == "xpiglit" ]; then
    RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND cd \$HOME/piglit.git; git fetch origin; git checkout wip/agomez/gtf_gl_es;"
fi

if [[ $1 == opengl-es* ]]; then
    RCR_CTS_RUNNER_TYPE="es32"
    RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND weston > /tmp/weston.log & sleep 5; export MESA_GLES_VERSION_OVERRIDE=3.2;"
    if [ x$2 == "xpiglit" ]; then
	RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND PIGLIT_KHR_GLES_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run khr_gles -n GLES-CTS-KHR-i965-\$TIMESTAMP /results/results/GLES-CTS-KHR-i965-\$TIMESTAMP; PIGLIT_KHR_NOCTX_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run khr_noctx -n NOCTX-CTS-KHR-i965-\$TIMESTAMP /results/results/NOCTX-CTS-KHR-i965-\$TIMESTAMP; PIGLIT_GTF_GLES_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run gtf_gles -n GLES-CTS-GTF-i965-\$TIMESTAMP /results/results/GLES-CTS-GTF-i965-\$TIMESTAMP; PIGLIT_DEQP_GLES2_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run deqp_gles2 -n GLES2-CTS-DEQP-i965-\$TIMESTAMP /results/results/GLES2-CTS-DEQP-i965-\$TIMESTAMP; PIGLIT_DEQP_GLES3_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run deqp_gles3 -n GLES3-CTS-DEQP-i965-\$TIMESTAMP /results/results/GLES3-CTS-DEQP-i965-\$TIMESTAMP; PIGLIT_DEQP_GLES31_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run deqp_gles31 -n GLES31-CTS-DEQP-i965-\$TIMESTAMP /results/results/GLES31-CTS-DEQP-i965-\$TIMESTAMP; PIGLIT_DEQP_EGL_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run deqp_egl -n EGL-CTS-DEQP-i965-\$TIMESTAMP /results/results/EGL-CTS-DEQP-i965-\$TIMESTAMP; for i in GLES-CTS-KHR-i965-\$TIMESTAMP NOCTX-CTS-KHR-i965-\$TIMESTAMP GLES-CTS-GTF-i965-\$TIMESTAMP GLES2-CTS-DEQP-i965-\$TIMESTAMP GLES3-CTS-DEQP-i965-\$TIMESTAMP GLES31-CTS-DEQP-i965-\$TIMESTAMP EGL-CTS-DEQP-i965-\$TIMESTAMP; do /home/local/piglit.git/piglit summary html -e pass /results/summary/\$i /results/results/\$i; done;"
    fi
else
    RCR_CTS_RUNNER_TYPE="gl46"
    RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND export MESA_GLSL_VERSION_OVERRIDE=460; export MESA_GL_VERSION_OVERRIDE=4.6;"
    if [ x$2 == "xpiglit" ]; then
	RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND PIGLIT_KHR_GL_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run khr_gl -t GL46 -n GL-CTS-KHR-i965-\$TIMESTAMP /results/results/GL-CTS-KHR-i965-\$TIMESTAMP; PIGLIT_KHR_NOCTX_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run khr_noctx -n NOCTX-CTS-KHR-i965-\$TIMESTAMP /results/results/NOCTX-CTS-KHR-i965-\$TIMESTAMP; PIGLIT_GTF_GL_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run gtf_gl -n GL-CTS-GTF-i965-\$TIMESTAMP /results/results/GL-CTS-GTF-i965-\$TIMESTAMP; PIGLIT_DEQP_EGL_BIN=/home/local/vk-gl-cts/build/external/openglcts/modules/glcts /home/local/piglit.git/piglit run deqp_egl -n EGL-CTS-DEQP-i965-\$TIMESTAMP /results/results/EGL-CTS-DEQP-i965-\$TIMESTAMP; for i in GL-CTS-KHR-i965-\$TIMESTAMP NOCTX-CTS-KHR-i965-\$TIMESTAMP GL-CTS-GTF-i965-\$TIMESTAMP EGL-CTS-DEQP-i965-\$TIMESTAMP; do /home/local/piglit.git/piglit summary html -e pass /results/summary/\$i /results/results/\$i; done;"
    fi
fi

RCR_DOCKER_TAG="vk-gl-cts.$1.cl.base"

if [ x$2 != "xpiglit" ]; then
    RCR_DOCKER_RUN_COMMAND="$RCR_DOCKER_RUN_COMMAND cd external/openglcts/modules/; mkdir -p /results/cts-runner/\$RCR_CTS_RUNNER_TYPE-\$TIMESTAMP; ./cts-runner --type=\$RCR_CTS_RUNNER_TYPE --logdir=/results/cts-runner/\$RCR_CTS_RUNNER_TYPE-\$TIMESTAMP;"
fi

docker pull "$RCR_DOCKER_REPOSITORY":"$RCR_DOCKER_TAG" && \
    docker run --privileged --rm -t -v /home/igalia/igalia/ci/piglit-results/agomez/:/results:Z \
           -v /home/igalia/agomez/docker-ssh:/home/local/.ssh:Z \
           -v /home/igalia/agomez/.ccache:/home/local/.ccache:Z \
           -e RCR_CTS_RUNNER_TYPE="$RCR_CTS_RUNNER_TYPE" \
           -e DISPLAY=unix"$DISPLAY" \
           -v /tmp/.X11-unix:/tmp/.X11-unix \
           "$RCR_DOCKER_REPOSITORY":"$RCR_DOCKER_TAG" /bin/bash -c "$RCR_DOCKER_RUN_COMMAND"
