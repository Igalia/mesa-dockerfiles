#!/bin/bash
#
#		Runs piglit test on a given set of mesa3D drivers
#

export LC_ALL=C

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY

MAKEFLAGS=-j$(getconf _NPROCESSORS_ONLN)
export MAKEFLAGS

#------------------------------------------------------------------------------
#			Function: check_verbosity
#------------------------------------------------------------------------------
#
# check if quiet and verbose are both passed:
# returns:
#   if it returns, everything is good
#   otherwise it exit's
check_verbosity() {
    if ${CDP_QUIET:-false} && ${CDP_VERBOSE:-false}; then
	echo ""
	echo "The --quiet and --verbose flags are incompatible"
	echo ""
	usage
	exit 1
    fi
}

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
	if $CDP_CLEAN; then
	    if $CDP_RUN_PIGLIT; then
		docker rmi igalia/mesa:piglit >&"${CDP_OUTPUT}" 2>&1
	    fi
	    if $CDP_RUN_VK_CTS || $CDP_RUN_GL_CTS; then
		docker rmi igalia/mesa:vk-gl-cts >&"${CDP_OUTPUT}" 2>&1
	    fi
	fi
    fi

    exit $1
}

#------------------------------------------------------------------------------
#			Function: header
#------------------------------------------------------------------------------
#
# prints a header, if not quiet
#   $1 - name to print out
# returns:
#   0 is success, an error code otherwise
function header {
    if ! $CDP_QUIET; then
	TIMESTAMP=`date +%Y%m%d%H%M%S`
	echo "Running $1 at $TIMESTAMP"
	echo ""
	df -h
	echo ""
    fi

    return 0
}

#------------------------------------------------------------------------------
#			Function: proper_driver
#------------------------------------------------------------------------------
#
# prints the proper driver given a test suite and proposed driver
#   $1 - the test suite
#   $2 - the proposed driver
function proper_driver {
    case $2 in
    i965|anv)
	(test "x$1" = "xvulkan" && printf "anv") || printf "i965"
	;;
    radeon|radv)
	(test "x$1" = "xvulkan" && printf "radv") || printf "radeon"
	;;
    *)
	printf "$2"
	;;
    esac
}

#------------------------------------------------------------------------------
#			Function: test_suites
#------------------------------------------------------------------------------
#
# prints the test suites names
function test_suites {
    $CDP_RUN_PIGLIT && printf "piglit "
    $CDP_RUN_VK_CTS && printf "vulkan "
    $CDP_RUN_GL_CTS && printf "opengl "
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

    if [ ! -d "${CCACHE_DIR}" ]; then
	echo ""
	echo "${CCACHE_DIR} directory doesn't exist."
	echo ""
	return 5
    fi

    check_local_changes
    if [ $? -ne 0 ]; then
	return 6
    fi

    git pull ${CDP_SILENCE}


    if $CDP_RUN_PIGLIT; then
	rocker build --pull -f Rockerfile.piglit --var TAG=piglit --var RELEASE="${CDP_RELEASE}" >&"${CDP_OUTPUT}" 2>&1
	CDP_TEST_SUITES="piglit $CDP_TEST_SUITES"
    fi

    if $CDP_RUN_GL_CTS || $CDP_RUN_VK_CTS; then
	cp Rockerfile.vk-gl-cts $HOME
	cd $HOME/LoaderAndValidationLayers
	git pull ${CDP_SILENCE}
	cd - > /dev/null
	cd $HOME/vk-gl-cts
	git pull ${CDP_SILENCE}
	cd - > /dev/null
	cd $HOME
	rocker build --pull -f Rockerfile.vk-gl-cts --var VIDEO_GID=`getent group video | cut -f3 -d:` --var TAG=vk-gl-cts --var RELEASE="${CDP_RELEASE}" >&"${CDP_OUTPUT}" 2>&1
	rm Rockerfile.vk-gl-cts
	cd - > /dev/null
    fi

    if $CDP_VERBOSE; then
	CDP_EXTRA_ARGS="--verbosity full $CDP_EXTRA_ARGS"
    elif $CDP_QUIET; then
	CDP_EXTRA_ARGS="--verbosity quiet $CDP_EXTRA_ARGS"
    fi

    for suite in $(test_suites); do
	for driver in $CDP_MESA_DRIVERS; do
	    corrected_driver=`proper_driver "$suite" "$driver"`
	    if ! $CDP_QUIET; then
		echo ""
		echo "Processing $suite test suite with driver $corrected_driver ..."
		echo ""
	    fi
	    if ! $CDP_DRY_RUN; then
		if [ "x$suite" = "xpiglit" ]; then
		    docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
			   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
			   -e FPR_EXTRA_ARGS="$CDP_EXTRA_ARGS" \
			   -e GL_DRIVER="$corrected_driver" igalia/mesa:piglit
		fi
		if [ "x$suite" = "xopengl" ] || [ "x$suite" = "xvulkan" ]; then
		    if [ "x$suite" = "xopengl" ]; then
			CDP_CTS_EXTRA_ARGS="$CDP_EXTRA_ARGS"
		    else
			CDP_CTS_EXTRA_ARGS="--vk-cts-all-concurrent $CDP_EXTRA_ARGS"
		    fi
		    docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
			   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
			   -e FPR_EXTRA_ARGS="$CDP_CTS_EXTRA_ARGS" \
			   -e CTS="$suite" \
			   -e GL_DRIVER="$corrected_driver" igalia/mesa:vk-gl-cts
		fi
	    fi
	done
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
  --no-clean              Do not clean the created image
  --quiet                 Be quiet
  --verbose               Be verbose
  --help                  Display this help and exit successfully
  --mesa-dockerfiles-dir  PATH to the mesa-dockerfiles.git repository
  --piglit-results-dir    PATH where to place the piglit results
  --docker-ccache-dir     PATH where for ccache's directory
  --run-vk-cts            Run vk-cts
  --run-gl-cts            Run gl-cts
  --run-piglit            Run piglit

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
    # Do not clean the created image
    --no-clean)
	CDP_CLEAN=false
	;;
    # Be quiet
    --quiet)
	CDP_QUIET=true
	check_verbosity
	;;
    # Be verbose
    --verbose)
	CDP_VERBOSE=true
	check_verbosity
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
	CCACHE_DIR=$1
	;;
    # Run vk-cts
    --run-vk-cts)
	CDP_RUN_VK_CTS=true
	;;
    # Run gl-cts
    --run-gl-cts)
	CDP_RUN_GL_CTS=true
	;;
    # Run piglit
    --run-piglit)
	CDP_RUN_PIGLIT=true
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
CCACHE_DIR="${CCACHE_DIR:-$HOME/i965/piglit-results/docker-ccache}"

# What tests to run?
# ------------------

CDP_RUN_VK_CTS="${CDP_RUN_VK_CTS:-false}"
CDP_RUN_GL_CTS="${CDP_RUN_GL_CTS:-false}"
CDP_RUN_PIGLIT="${CDP_RUN_PIGLIT:-false}"

# Quiet?
# ------

CDP_QUIET="${CDP_QUIET:-false}"

# Verbose?
# --------

CDP_VERBOSE="${CDP_VERBOSE:-false}"

# dry run?
# --------

CDP_DRY_RUN="${CDP_DRY_RUN:-false}"

# Cleaning?
# ---------

CDP_CLEAN="${CDP_CLEAN:-true}"

# ---

if ${CDP_VERBOSE}; then
    CDP_OUTPUT=1
    CDP_SILENCE=""
else
    CDP_OUTPUT=/dev/null
    CDP_SILENCE="-q"
fi

header $0

run_piglit_tests

cleanup $?
