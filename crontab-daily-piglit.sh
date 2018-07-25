#!/bin/bash
#
#		Runs piglit test on a given set of mesa3D drivers
#
# This script is intended to run automatically as a cronjob, making
# use of full-piglit-run.sh
#
# Example:
#
# $ crontab -e
# ...
# 0 3 * * * bash <path_to>/mesa-dockerfiles.git/crontab-daily-piglit.sh --run-piglit test/mesa-17.2 --run-vk-cts test/vk/mesa-17.2 --run-gl-cts test/gl/mesa-17.2 --release pre-release-17.2.debug i965

export LC_ALL=C

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)

DISPLAY="${DISPLAY:-:0.0}"
export -p DISPLAY

MAKEFLAGS=-j$(getconf _NPROCESSORS_ONLN)
export MAKEFLAGS


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
	CDP_PROGRESS_FLAG="-q"
    fi

    if [ "x$1" == "xquiet" ]; then
	exec 2>/dev/null
	exec 9>/dev/null
    fi
}


#------------------------------------------------------------------------------
#			Function: check_local_changes
#------------------------------------------------------------------------------
#
check_local_changes() {
    git diff --quiet HEAD
    if [ $? -ne 0 ]; then
	printf "%s\n" \
	       "" \
	       "Uncommitted changes found. Did you forget to commit? Aborting." \
	       "" \
	       "You can perform a 'git stash' to save your local changes and" \
	       "a 'git stash apply' to recover them afterwards." \
	       "" >&2
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
	printf "%s\n" "Error: the '$option' option is missing its required argument." >&2
	usage
	exit 1
    fi

    # does the argument look like an option?
    echo $arg | $CDP_GREP "^-" > /dev/null
    if [ $? -eq 0 ]; then
	printf "%s\n" "Error: the argument '$arg' of option '$option' looks like an option itself." >&2
	usage
	exit 1
    fi
}

#------------------------------------------------------------------------------
#			Function: cleanup
#------------------------------------------------------------------------------
#
# cleans up the environment and exits with a given error code
#   $1 - the error code to exit with
# returns:
#   it exits
function cleanup {
    if [ "x$1" == "x0" ]; then
	if $CDP_CLEAN; then
	    if $CDP_RUN_PIGLIT; then
		docker rmi "$CDP_DOCKER_IMAGE":piglit
	    fi
	    if $CDP_RUN_GL_CTS; then
		docker rmi "$CDP_DOCKER_IMAGE":gl-cts
	    fi
	    if $CDP_RUN_VK_CTS; then
		docker rmi "$CDP_DOCKER_IMAGE":vk-cts
	    fi
	fi
    fi
    restore_redirection

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
    CDP_TIMESTAMP=`date +%Y%m%d%H%M%S`
    CDP_SPACE=$(df -h)
    printf "%s\n" "Running $1 at $CDP_TIMESTAMP" "" "$CDP_SPACE" "" >&9

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
#			Function: unique_icd_filename
#------------------------------------------------------------------------------
#
# prints an unique ICD filename based on the provided vulkan driver
#   $1 - a vulkan driver
function unique_icd_filename {
    case $1 in
    anv)
	# Asumming a lot of things here: path and x86_64 arch. Meh ...
	printf "/usr/local/share/vulkan/icd.d/intel_icd.x86_64.json"
	;;
    radv)
	# Asumming a lot of things here: path and x86_64 arch. Meh ...
	printf "/usr/local/share/vulkan/icd.d/radeon_icd.x86_64.json"
	;;
    *)
	printf ""
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
	printf "%s\n" "Error: a release has to be provided." >&2
	usage
	return 1
    fi

    if [ "${CDP_MESA_DRIVERS:-x}" == "x" ]; then
	printf "%s\n" "Error: at least one mesa3d driver must be passed." >&2
	usage
	return 2
    fi

    if [ -d "${CDP_MESA_DOCKERFILES_DIR}" ]; then
	cd "${CDP_MESA_DOCKERFILES_DIR}"
    else
	printf "%s\n" "Error: ${CDP_MESA_DOCKERFILES_DIR} directory doesn't exist." >&2
	return 3
    fi

    if [ ! -d "${CDP_PIGLIT_RESULTS_DIR}" ]; then
	printf "%s\n" "Error: ${CDP_PIGLIT_RESULTS_DIR} directory doesn't exist." >&2
	return 4
    fi

    if [ ! -d "${CCACHE_DIR}" ]; then
	printf "%s\n" "Error: ${CCACHE_DIR} directory doesn't exist." >&2
	return 5
    fi

    check_local_changes
    if [ $? -ne 0 ]; then
	return 6
    fi

    git pull $CDP_PROGRESS_FLAG

    if [ ! -z "$CDP_DOCKER_USER" ]; then
       docker login -u "$CDP_DOCKER_USER" -p "$CDP_DOCKER_PASSWORD" "${CDP_DOCKER_IMAGE%%/*}"
    fi

    if $CDP_RUN_PIGLIT; then
	DOCKER_IMAGE="$CDP_DOCKER_IMAGE" \
	rocker build --pull -f Rockerfile.piglit --var DEBUG=true --var TEST_BRANCH="${CDP_PIGLIT_BRANCH}" --var FPR_BRANCH="${CDP_FPR_BRANCH}" --var TAG=piglit --var RELEASE="${CDP_RELEASE}"
	CDP_TEST_SUITES="piglit $CDP_TEST_SUITES"
    fi

    if $CDP_RUN_GL_CTS; then
	cp Rockerfile.vk-gl-cts $HOME
	cd $HOME/Vulkan-Headers
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/Vulkan-Loader
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/Vulkan-ValidationLayers
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/vk-gl-cts
	git checkout $CDP_PROGRESS_FLAG $CDP_GL_CTS_BRANCH
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME
	DOCKER_IMAGE="$CDP_DOCKER_IMAGE" \
	rocker build --pull -f Rockerfile.vk-gl-cts --var VIDEO_GID=`getent group video | cut -f3 -d:` --var DEBUG=true --var FPR_BRANCH="${CDP_FPR_BRANCH}" --var TAG=gl-cts --var RELEASE="${CDP_RELEASE}"
	rm Rockerfile.vk-gl-cts
	cd -
    fi

    if $CDP_RUN_VK_CTS; then
	cp Rockerfile.vk-gl-cts $HOME
	cd $HOME/Vulkan-Headers
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/Vulkan-Loader
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/Vulkan-ValidationLayers
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME/vk-gl-cts
	git checkout $CDP_PROGRESS_FLAG $CDP_VK_CTS_BRANCH
	git pull $CDP_PROGRESS_FLAG
	cd -
	cd $HOME
	DOCKER_IMAGE="$CDP_DOCKER_IMAGE" \
	rocker build --pull -f Rockerfile.vk-gl-cts --var VIDEO_GID=`getent group video | cut -f3 -d:` --var DEBUG=true --var FPR_BRANCH="${CDP_FPR_BRANCH}" --var TAG=vk-cts --var RELEASE="${CDP_RELEASE}"
	rm Rockerfile.vk-gl-cts
	cd -
    fi

    CDP_EXTRA_ARGS="--verbosity $CDP_VERBOSITY $CDP_EXTRA_ARGS"
    $CDP_CREATE_PIGLIT_REPORT && CDP_EXTRA_ARGS="--create-piglit-report $CDP_EXTRA_ARGS"

    for suite in $(test_suites); do
	for driver in $CDP_MESA_DRIVERS; do
	    corrected_driver=`proper_driver "$suite" "$driver"`
	    printf "%s\n" "" "Processing $suite test suite with driver $corrected_driver ..." "" >&9
	    icd_filename=`unique_icd_filename "$corrected_driver"`
	    printf "%s\n" "" "Chosen ICD file is $icd_filename ..." "" >&9
	    if ! $CDP_DRY_RUN; then

		# We restore the redirection so the output is managed
		# by the commands inside "docker run"
		restore_redirection
		case "x$suite" in
		    "xpiglit" )
			docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
			       -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
			       -e FPR_EXTRA_ARGS="$CDP_EXTRA_ARGS" \
			       -e GL_DRIVER="$corrected_driver" "$CDP_DOCKER_IMAGE":piglit
		        ;;
		    "xopengl" )
			docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
			       -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
			       -e FPR_EXTRA_ARGS="$CDP_EXTRA_ARGS" \
			       -e CTS="$suite" \
			       -e GL_DRIVER="$corrected_driver" "$CDP_DOCKER_IMAGE":gl-cts
		        ;;
		    "xvulkan" )
			docker run --privileged --rm -t -v "${CDP_PIGLIT_RESULTS_DIR}":/results:Z \
			       -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
			       -e FPR_EXTRA_ARGS="--vk-cts-all-concurrent $CDP_EXTRA_ARGS" \
			       -e CTS="$suite" \
			       -e VK_ICD_FILENAMES="$icd_filename" \
			       -e GL_DRIVER="$corrected_driver" "$CDP_DOCKER_IMAGE":vk-cts
		        ;;
		    *)
			apply_verbosity "$CDP_VERBOSITY"
			printf "%s\n" "Error: Suite $suite is not a valid one. This should never happen!!!" >&2
			return 7
			;;
		esac
		apply_verbosity "$CDP_VERBOSITY"
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

Usage: $basename [options] --release <tag> <driver>

Where "driver" is one of [i965|anv|llvmpipe|swr|softpipe]

Options:
  --dry-run                        Does everything except running the tests
  --no-clean                       Do not clean the created image
  --verbosity [full|normal|quiet]  Which verbosity level to use
                                   [full|normal|quite]. Default, normal.
  --help                           Display this help and exit successfully
  --release <tag>                  Use the release docker image tagged as <tag>
  --mesa-dockerfiles-dir <path>    <path> to the mesa-dockerfiles.git
                                   repository
  --piglit-results-dir <path>      <path> where to place the piglit results
  --docker-ccache-dir <path>       <path> where for ccache's directory
  --run-vk-cts <branch>            Run against the vk-cts <branch>
  --run-gl-cts <branch>            Run against the gl-cts <branch>
  --run-piglit <branch>            Run against the piglit <branch>
  --fpr-branch <branch>            full-piglit-run.sh' <branch>
  --create-piglit-report           Create results report
  --docker-image                   Docker base image.
  --docker-user                    Docker user.
  --docker-password                Docker password.

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
    # Which verbosity level to use [full|normal|quite]. Default, normal.
    --verbosity)
	check_option_args $1 $2
	shift
	export CDP_VERBOSITY=$1
	;;
    # Display this help and exit successfully
    --help)
	usage
	exit 0
	;;
    # Use the release docker image tagged as <tag>
    --release)
	check_option_args $1 $2
	shift
	CDP_RELEASE=$1
	;;
    # <path> to the mesa-dockerfiles.git repository
    --mesa-dockerfiles-dir)
	check_option_args $1 $2
	shift
	CDP_MESA_DOCKERFILES_DIR=$1
	;;
    # <path> where to place the piglit results
    --piglit-results-dir)
	check_option_args $1 $2
	shift
	CDP_PIGLIT_RESULTS_DIR=$1
	;;
    # <path> where for ccache's directory
    --docker-ccache-dir)
	check_option_args $1 $2
	shift
	CCACHE_DIR=$1
	;;
    # Run against the vk-cts <branch>
    --run-vk-cts)
	CDP_RUN_VK_CTS=true
	check_option_args $1 $2
	shift
	CDP_VK_CTS_BRANCH=$1
	;;
    # Run against the gl-cts <branch>
    --run-gl-cts)
	CDP_RUN_GL_CTS=true
	check_option_args $1 $2
	shift
	CDP_GL_CTS_BRANCH=$1
	;;
    # Run against the piglit <branch>
    --run-piglit)
	CDP_RUN_PIGLIT=true
	check_option_args $1 $2
	shift
	CDP_PIGLIT_BRANCH=$1
	;;
    # full-piglit-run.sh' <branch>
    --fpr-branch)
	check_option_args $1 $2
	shift
	CDP_FPR_BRANCH=$1
	;;
    # Create results report
    --create-piglit-report)
	CDP_CREATE_PIGLIT_REPORT=true
	;;
    # Docker base image
    --docker-image)
	check_option_args $1 $2
	shift
        CDP_DOCKER_IMAGE=$1
	;;
    # Docker user
    --docker-user)
	check_option_args $1 $2
	shift
        CDP_DOCKER_USER=$1
	;;
    # Docker password
    --docker-password)
	check_option_args $1 $2
	shift
        CDP_DOCKER_PASSWORD=$1
	;;
    --*)
	printf "%s\n" "Error: unknown option: $1" >&2
	usage
	exit 1
	;;
    -*)
	printf "%s\n" "Error: unknown option: $1" >&2
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

# Which FPR branch to use?
# ------------------------

CDP_FPR_BRANCH="${CDP_FPR_BRANCH:-master}"

# Docker settings
# ---------------

CDP_DOCKER_IMAGE="${CDP_DOCKER_IMAGE:-igalia/mesa}"

# Verbose?
# --------

CDP_VERBOSITY="${CDP_VERBOSITY:-normal}"

check_verbosity "$CDP_VERBOSITY"
if [ $? -ne 0 ]; then
    exit 13
fi

apply_verbosity "$CDP_VERBOSITY"

# dry run?
# --------

CDP_DRY_RUN="${CDP_DRY_RUN:-false}"

# Cleaning?
# ---------

CDP_CLEAN="${CDP_CLEAN:-true}"

# Create a report against the reference result?
# ---------------------------------------------

CDP_CREATE_PIGLIT_REPORT="${CDP_CREATE_PIGLIT_REPORT:-false}"

# ---

header $0

run_piglit_tests

cleanup $?
