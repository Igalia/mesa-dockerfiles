#!/bin/bash
#
#		Runs piglit test on a given set of mesa3D drivers
#

export LC_ALL=C

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY

#------------------------------------------------------------------------------
#			Function: check_local_changes
#------------------------------------------------------------------------------
#
check_local_changes() {
    git diff --quiet HEAD > /dev/null 2>&1
    if [ $? -ne 0 ]; then
	echo ""
	echo "Uncommitted changes found. Did you forget to commit? Aborting."
	echo ""
	echo "You can perform a 'git stash' to save your local changes and"
	echo "a 'git stash apply' to recover them afterwards."
	echo ""
	return 1
    fi
    return 0
}

#------------------------------------------------------------------------------
#			Function: check_option_args
#------------------------------------------------------------------------------
#
# perform sanity checks on cmdline args which require arguments
# arguments:
#   $1 - the option being examined
#   $2 - the argument to the option
# returns:
#   if it returns, everything is good
#   otherwise it exit's
check_option_args() {
    option=$1
    arg=$2

    # check for an argument
    if [ x"$arg" = x ]; then
	echo ""
	echo "Error: the '$option' option is missing its required argument."
	echo ""
	usage
	exit 1
    fi

    # does the argument look like an option?
    echo $arg | $CDP_GREP "^-" > /dev/null
    if [ $? -eq 0 ]; then
	echo ""
	echo "Error: the argument '$arg' of option '$option' looks like an option itself."
	echo ""
	usage
	exit 1
    fi
}

#------------------------------------------------------------------------------
#			Function: cleanup
#------------------------------------------------------------------------------
#
# cleans up the environment and exits with a give error code
#   $1 - the error code to exit with
# returns:
#   it exits
function cleanup {
    if [ "x$1" == "x0" ]; then
        docker rmi image-piglit >&"${CDP_OUTPUT}" 2>&1
    fi

    exit $1
}

#------------------------------------------------------------------------------
#			Function: run_piglit_tests
#------------------------------------------------------------------------------
#
# performs the execution of the piglit tests
# returns:
#   0 is success, an error code otherwise
function run_piglit_tests {
    if [ "${CDP_RELEASE:-x}" == "x" ]; then
	echo ""
	echo "A release has to be provided."
	echo ""
	usage
	return 1
    fi
    if [ "${CDP_MESA_DRIVERS:-x}" == "x" ]; then
	echo ""
	echo "At least one mesa3d driver must be passed."
	echo ""
	usage
	return 2
    fi

    if [ -d "${CDP_MESA_DOCKERFILES_DIR}" ]; then
	cd "${CDP_MESA_DOCKERFILES_DIR}"
    else
	echo ""
	echo "${CDP_MESA_DOCKERFILES_DIR} directory doesn't exist."
	echo ""
	return 3
    fi

    if [ ! -d "${CDP_PIGLIT_RESULTS_DIR}" ]; then
	echo ""
	echo "${CDP_PIGLIT_RESULTS_DIR} directory doesn't exist."
	echo ""
	return 4
    fi

    if [ ! -d "${CDP_DOCKER_CCACHE_DIR}" ]; then
	echo ""
	echo "${CDP_DOCKER_CCACHE_DIR} directory doesn't exist."
	echo ""
	return 5
    fi

    check_local_changes
    if [ $? -ne 0 ]; then
	return 6
    fi

    git pull ${CDP_QUIET}

    dj ${CDP_QUIET} -d Dockerfile.piglit.jinja -o Dockerfile -e RELEASE="${CDP_RELEASE}" -e MAKEFLAGS=-j2
    # CDP_QUIET is not enough for docker build.
    # Therefore, we mute with CDP_OUT as with other commands ...
    docker build ${CDP_QUIET} --pull -f Dockerfile -t image-piglit . >&"${CDP_OUTPUT}" 2>&1
    rm Dockerfile
    docker run -v "${CDP_DOCKER_CCACHE_DIR}":/home/local/.ccache \
	   -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
	   --name container-piglit image-piglit \
	   "/bin/sh" "-c" "cmake . && make" >&"${CDP_OUTPUT}" 2>&1
    docker commit container-piglit image-piglit >&"${CDP_OUTPUT}" 2>&1
    docker rm container-piglit >&"${CDP_OUTPUT}" 2>&1

    for i in $CDP_MESA_DRIVERS; do
	if $CDP_DRY_RUN; then
	    $CDP_VERBOSE && echo "Processing driver $i ..."
	else
	    docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_VERBOSE=$CDP_VERBOSE \
		   -e GL_DRIVER=$i image-piglit \
		   "/bin/sh" "-c" "cat /home/local/mesa-head.txt >> /results/mesa-head.txt && cat /home/local/piglit-head.txt >> /results/piglit-head.txt && export MESA_COMMIT=\$(grep commit /home/local/mesa-head.txt | cut -d \" \" -f 2) && export FPR_CREATE_PIGLIT_REPORT=true && export FPR_RUN_PIGLIT=true && export FPR_PIGLIT_PATH=/home/local/piglit && export FPR_PIGLIT_REPORTS_PATH=/results && /home/local/full-piglit-run.sh \$GL_DRIVER \$MESA_COMMIT"
	fi
    done

    return 0
}

#------------------------------------------------------------------------------
#			Function: usage
#------------------------------------------------------------------------------
# Displays the script usage and exits successfully
#
usage() {
    basename="`expr "//$0" : '.*/\([^/]*\)'`"
    cat <<HELP

Usage: $basename [options] --release <release> path...

Where "path" is a relative path to a git module, including '.'.

Options:
  --dry-run               Does everything except running the tests
  --verbose               Be verbose
  --help                  Display this help and exit successfully
  --mesa-dockerfiles-dir  PATH to the mesa-dockerfiles.git repository
  --piglit-results-dir    PATH where to place the piglit results
  --docker-ccache-dir     PATH where for ccache's directory

HELP
}

#------------------------------------------------------------------------------
#			Script main line
#------------------------------------------------------------------------------
#

# Choose which grep program to use (on Solaris, must be gnu grep)
if [ "x$CDP_GREP" = "x" ] ; then
    if [ -x /usr/gnu/bin/grep ] ; then
	CDP_GREP=/usr/gnu/bin/grep
    else
	CDP_GREP=grep
    fi
fi

# Process command line args
while [ $# != 0 ]
do
    case $1 in
    # Does everything except running the tests
    --dry-run)
	CDP_DRY_RUN=true
	;;
    # Be verbose
    --verbose)
	CDP_VERBOSE=true
	;;
    # Display this help and exit successfully
    --help)
	usage
	exit 0
	;;
    # Release the git modules specified in <file>
    --release)
	check_option_args $1 $2
	shift
	CDP_RELEASE=$1
	;;
    # PATH to the mesa-dockerfiles.git repository
    --mesa-dockerfiles-dir)
	check_option_args $1 $2
	shift
	CDP_MESA_DOCKERFILES_DIR=$1
	;;
    # PATH where to place the piglit results
    --piglit-results-dir)
	check_option_args $1 $2
	shift
	CDP_PIGLIT_RESULTS_DIR=$1
	;;
    # PATH where for ccache's directory
    --docker-ccache-dir)
	check_option_args $1 $2
	shift
	CDP_DOCKER_CCACHE_DIR=$1
	;;
    --*)
	echo ""
	echo "Error: unknown option: $1"
	echo ""
	usage
	exit 1
	;;
    -*)
	echo ""
	echo "Error: unknown option: $1"
	echo ""
	usage
	exit 1
	;;
    *)
	CDP_MESA_DRIVERS="${CDP_MESA_DRIVERS} $1"
	;;
    esac

    shift
done

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

# dry run?
# --------

CDP_DRY_RUN="${CDP_DRY_RUN:-false}"

# ---

if ${CDP_VERBOSE}; then
    CDP_OUTPUT=1
    CDP_QUIET=""
else
    CDP_OUTPUT=/dev/null
    CDP_QUIET="-q"
fi

run_piglit_tests

cleanup $?
