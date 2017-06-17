#!/bin/bash
#
# This script is intended to run automatically as a cronjob, making
# use of full-piglit-run.sh
#
# Example:
#
# $ crontab -e
# ...
# 0 3 * * * <path_to>/f-p-r-cronjob.sh --mesa-commit "mesa-remote/mesa-branch" --vk-gl-cts-commit "vk-gl-cts-remote/vk-gl-cts-branch"

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
    fi

    if [ "x$1" == "xquiet" ]; then
	exec 2>/dev/null
	exec 9>/dev/null
    fi
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
function check_option_args() {
    option=$1
    arg=$2

    # check for an argument
    if [ x"$arg" = x ]; then
	printf "Error: the '$option' option is missing its required argument.\n" >&2
	usage
	exit 2
    fi

    # does the argument look like an option?
    echo $arg | $CFPR_GREP "^-" > /dev/null
    if [ $? -eq 0 ]; then
	printf "Error: the argument '$arg' of option '$option' looks like an option itself.\n" >&2
	usage
	exit 3
    fi
}


#------------------------------------------------------------------------------
#			Function: sanity_check
#------------------------------------------------------------------------------
#
# perform sanity check on the passed parameters:
# arguments:
#   $1 - an existing mesa's commit id
#   $2 - an existing VK-GL-CTS' commit id
# returns:
#   0 is success, an error code otherwise
function sanity_check() {
    if [ "x$1" == "x" ] || [ "x$2" == "x" ]; then
	printf "Error: Missing parameters.\n" >&2
	usage
	return 2
    fi

    pushd "$CFPR_MESA_PATH"
    git fetch origin
    git show -s --pretty=format:%h "$1" > /dev/null
    CFPR_RESULT=$?
    popd
    if [ $CFPR_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: mesa's commit id doesn't exist in the repository." "" >&2
	usage
	return 3
    fi

    pushd "$CFPR_VK_GL_CTS_PATH"
    git fetch origin
    git show -s --pretty=format:%h "$2" > /dev/null
    CFPR_RESULT=$?
    popd
    if [ $CFPR_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: VK-GL-CTS' commit id doesn't exist in the repository." "" >&2
	usage
	return 4
    fi

    return 0
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
    CFPR_TIMESTAMP=$(date +%Y%m%d%H%M%S)
    CFPR_SPACE=$(df -h)
    printf "%s\n" "Running $1 at $CFPR_TIMESTAMP" "" "$CFPR_SPACE" "" >&9

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_mesa
#------------------------------------------------------------------------------
#
# builds a specific commit of mesa or the latest common commit with master
#   $1 - whether to build the merge base against master or not
# outputs:
#   the requested commit hash
# returns:
#   0 is success, an error code otherwise
function build_mesa() {
    rm -rf "$CFPR_TEMP_PATH/mesa"
    git clone "$CFPR_MESA_PATH" "$CFPR_TEMP_PATH/mesa"
    pushd "$CFPR_MESA_PATH"
    CFPR_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CFPR_TEMP_PATH/mesa"
    git remote set-url origin "$CFPR_ORIGIN_URL"
    git fetch origin
    git branch -m old
    if $1; then
	COMMIT=$(git merge-base origin/master "$CFPR_MESA_BRANCH")
    else
	COMMIT="$CFPR_MESA_BRANCH"
    fi
    git checkout -b working "$COMMIT"
    git branch -D old
    CFPR_MESA_COMMIT=$(git show -s --pretty=format:%h "$COMMIT")
    wget https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/master/Rockerfile.mesa
    # make check is failing right now and we don't really need it
    sed -e 's/&& make check//g' -i Rockerfile.mesa
    rocker build -f Rockerfile.mesa --var BUILD="autotools" --var LLVM="3.9" --var DEBUG=true --var TAG=released-17.1.2."$CFPR_MESA_COMMIT"
    popd

    return 0
}


#------------------------------------------------------------------------------
#			Function: clean_mesa
#------------------------------------------------------------------------------
#
# cleans the used mesa's worktree
# returns:
#   0 is success, an error code otherwise
function clean_mesa() {
    rm -rf "$CFPR_TEMP_PATH/mesa"
    if $CFPR_CLEAN; then
	docker rmi igalia/mesa:released-17.1.2."$CFPR_MESA_COMMIT"
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_vk_gl_cts
#------------------------------------------------------------------------------
#
# builds a specific commit of vk-gl-cts
# returns:
#   0 is success, an error code otherwise
function build_vk_gl_cts() {
    rm -rf "$CFPR_TEMP_PATH/LoaderAndValidationLayers"
    git clone "$CFPR_VK_LOADER_PATH" "$CFPR_TEMP_PATH/LoaderAndValidationLayers"
    pushd "$CFPR_VK_LOADER_PATH"
    CFPR_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CFPR_TEMP_PATH/LoaderAndValidationLayers"
    git remote set-url origin "$CFPR_ORIGIN_URL"
    git fetch origin
    git branch -m old
    git checkout -b working origin/master
    git branch -D old
    popd

    rm -rf "$CFPR_TEMP_PATH/vk-gl-cts"
    git clone "$CFPR_VK_GL_CTS_PATH" "$CFPR_TEMP_PATH/vk-gl-cts"
    pushd "$CFPR_VK_GL_CTS_PATH"
    CFPR_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CFPR_TEMP_PATH/vk-gl-cts"
    git remote set-url origin "$CFPR_ORIGIN_URL"
    git fetch origin
    git branch -m old
    git checkout -b working "$CFPR_VK_GL_CTS_BRANCH"
    git branch -D old
    popd
    pushd "$CFPR_TEMP_PATH"
    wget https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/master/Rockerfile.vk-gl-cts
    rocker build -f Rockerfile.vk-gl-cts --var VIDEO_GID=`getent group video | cut -f3 -d:` --var TAG=vk-gl-cts --var RELEASE=released-17.1.2."$CFPR_MESA_COMMIT"
    popd

    return 0
}


#------------------------------------------------------------------------------
#			Function: clean_vk_gl_cts
#------------------------------------------------------------------------------
#
# cleans the used vk_gl_cts's worktree
# returns:
#   0 is success, an error code otherwise
function clean_vk_gl_cts() {
    rm -rf "$CFPR_TEMP_PATH/vk-gl-cts"
    rm -f "$CFPR_TEMP_PATH/Rockerfile.vk-gl-cts"
    if $CFPR_CLEAN; then
	docker rmi igalia/mesa:vk-gl-cts
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_piglit
#------------------------------------------------------------------------------
#
# builds a specific commit of piglit
# returns:
#   0 is success, an error code otherwise
function build_piglit() {
    rm -rf "$CFPR_TEMP_PATH/piglit"
    mkdir -p "$CFPR_TEMP_PATH/piglit"
    pushd "$CFPR_TEMP_PATH/piglit"
    wget https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/master/Rockerfile.piglit
    rocker build -f Rockerfile.piglit --var TAG=piglit --var RELEASE=released-17.1.2."$CFPR_MESA_COMMIT"
    popd

    return 0
}


#------------------------------------------------------------------------------
#			Function: clean_piglit
#------------------------------------------------------------------------------
#
# cleans the used piglit's worktree
# returns:
#   0 is success, an error code otherwise
function clean_piglit() {
    rm -rf "$CFPR_TEMP_PATH/piglit"
    if $CFPR_CLEAN; then
	docker rmi igalia/mesa:piglit
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: create_piglit_reference
#------------------------------------------------------------------------------
#
# creates the soft link to the piglit reference run
#   $1 - the driver for which to create the reference
# returns:
#   0 is success, an error code otherwise
function create_piglit_reference() {
    if [ "x$1" == "x" ]; then
	return -1
    fi

    ln -sfr $(ls -d $CFPR_PIGLIT_RESULTS_DIR/results/all-"$1"* | tail -1) -T $CFPR_PIGLIT_RESULTS_DIR/reference/all-"$1"

    return 0
}


#------------------------------------------------------------------------------
#			Function: create_gl_cts_reference
#------------------------------------------------------------------------------
#
# creates the soft link to the GL-CTS reference run
#   $1 - the driver for which to create the reference
# returns:
#   0 is success, an error code otherwise
function create_gl_cts_reference() {
    if [ "x$1" == "x" ]; then
	return -1
    fi

    ln -sfr $(ls -d $CFPR_PIGLIT_RESULTS_DIR/results/GL-CTS-"$1"* | tail -1) -T $CFPR_PIGLIT_RESULTS_DIR/reference/GL-CTS-"$1"

    return 0
}


#------------------------------------------------------------------------------
#			Function: create_vk_cts_reference
#------------------------------------------------------------------------------
#
# creates the soft link to the VK-CTS reference run
#   $1 - the driver for which to create the reference
# returns:
#   0 is success, an error code otherwise
function create_vk_cts_reference() {
    if [ "x$1" == "x" ]; then
	return -1
    fi

    ln -sfr $(ls -d $CFPR_PIGLIT_RESULTS_DIR/results/VK-CTS-"$1"* | tail -1) -T $CFPR_PIGLIT_RESULTS_DIR/reference/VK-CTS-"$1"

    return 0
}


#------------------------------------------------------------------------------
#			Function: run_tests
#------------------------------------------------------------------------------
#
# performs the execution of the tests
# returns:
#   0 is success, an error code otherwise
function run_tests {

    if [ ! -d "${CFPR_PIGLIT_RESULTS_DIR}" ]; then
	printf "%s\n" "Error: ${CFPR_PIGLIT_RESULTS_DIR} directory doesn't exist." >&2
	return 4
    fi

    header

    mkdir -p "$CFPR_TEMP_PATH/jail"

    pushd "$CFPR_TEMP_PATH/jail"

    build_mesa $CFPR_MERGE_BASE_RUN

    CFPR_EXTRA_ARGS="--verbosity $CFPR_VERBOSITY $CFPR_EXTRA_ARGS"

    if $CFPR_RUN_PIGLIT; then
    	build_piglit

	# We restore the redirection so the output is managed by the
	# commands inside "docker run"
	restore_redirection

	docker run --privileged --rm -t -v "${CFPR_PIGLIT_RESULTS_DIR}":/results:Z \
	       -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
	       -e FPR_EXTRA_ARGS="$CFPR_EXTRA_ARGS" \
	       -e GL_DRIVER="i965" igalia/mesa:piglit

	apply_verbosity "$CFPR_VERBOSITY"

	$CFPR_MERGE_BASE_RUN && create_piglit_reference "i965"

    	clean_piglit
    fi

    if $CFPR_RUN_GL_CTS || $CFPR_RUN_VK_CTS; then
    	build_vk_gl_cts

	if $CFPR_RUN_GL_CTS; then
    	    printf "%s\n" "" "Checking GL CTS progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CFPR_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="$CFPR_EXTRA_ARGS" \
		   -e CTS="opengl" \
		   -e GL_DRIVER="i965" igalia/mesa:vk-gl-cts

	    apply_verbosity "$CFPR_VERBOSITY"

	    $CFPR_MERGE_BASE_RUN && create_gl_cts_reference "i965"
	fi

	if $CFPR_RUN_VK_CTS; then
    	    printf "%s\n" "" "Checking VK CTS progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CFPR_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="--vk-cts-all-concurrent $CFPR_EXTRA_ARGS" \
		   -e CTS="vulkan" \
		   -e GL_DRIVER="anv" igalia/mesa:vk-gl-cts

	    apply_verbosity "$CFPR_VERBOSITY"

	    $CFPR_MERGE_BASE_RUN && create_vk_cts_reference "anv"
	fi

    	clean_vk_gl_cts
    fi

    clean_mesa

    popd
    rm -rf "$CFPR_TEMP_PATH/"

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

Usage: $basename [options] --mesa-commit <mesa-commit-id> --vk-gl-cts-commit <vk-gl-cts-commit-id> --piglit-commit <piglit-commit-id>

Options:
  --help                  Display this help and exit successfully
  --verbosity             Which verbosity level to use [full|normal|quite]. Default, normal.
  --no-clean              Do not clean the created images
  --force-clean           Forces the cleaning of the working env
  --base-path             PATH from which to create the rest of the relative paths
  --tmp-path              PATH in which to do the temporary work
  --mesa-path             PATH to the mesa repository
  --vk-gl-cts-path        PATH to the vk-gl-cts repository
  --vk-loader-path        PATH to the LoaderAndValidationLayers repository
  --piglit-results-dir    PATH where to place the piglit results
  --mesa-commit           mesa commit to use
  --vk-gl-cts-commit      VK-GL-CTS commit to use
  --merge-base-run        merge-base run
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
	CFPR_GREP=/usr/gnu/bin/grep
    else
	CFPR_GREP=grep
    fi
fi


# Process command line args
while [ $# != 0 ]
do
    case $1 in
    # Display this help and exit successfully
    --help)
	usage
	exit 0
	;;
    # Which verbosity level to use [full|normal|quite]. Default, normal.
    --verbosity)
	check_option_args $1 $2
	shift
	CFPR_VERBOSITY=$1
	;;
    # Do not clean the created images
    --no-clean)
	CFPR_CLEAN=false
	;;
    # Forces the cleaning of the working env
    --force-clean)
	CFPR_FORCE_CLEAN=true
	;;
    # PATH from which to create the rest of the relative paths
    --base-path)
	check_option_args $1 $2
	shift
	CFPR_BASE_PATH=$1
	;;
    # PATH in which to do the temporary work
    --tmp-path)
	check_option_args $1 $2
	shift
	CFPR_TEMP_PATH=$1
	;;
    # PATH to the mesa repository
    --mesa-path)
	check_option_args $1 $2
	shift
	CFPR_MESA_PATH=$1
	;;
    # PATH to the vk-gl-cts repository
    --vk-gl-cts-path)
	check_option_args $1 $2
	shift
	CFPR_VK_GL_CTS_PATH=$1
	;;
    # PATH to the LoaderAndValidationLayers repository
    --vk-loader-path)
	check_option_args $1 $2
	shift
	CFPR_VK_LOADER_PATH=$1
	;;
    # PATH where to place the piglit results
    --piglit-results-dir)
	check_option_args $1 $2
	shift
	CFPR_PIGLIT_RESULTS_DIR=$1
	;;
    # mesa commit to use
    --mesa-commit)
	check_option_args $1 $2
	shift
	CFPR_MESA_BRANCH=$1
	;;
    # VK-GL-CTS commit to use
    --vk-gl-cts-commit)
	check_option_args $1 $2
	shift
	CFPR_VK_GL_CTS_BRANCH=$1
	;;
    # merge-base run
    --merge-base-run)
	CFPR_MERGE_BASE_RUN=true
	;;
    # Run vk-cts
    --run-vk-cts)
	CFPR_RUN_VK_CTS=true
	;;
    # Run gl-cts
    --run-gl-cts)
	CFPR_RUN_GL_CTS=true
	;;
    # Run piglit
    --run-piglit)
	CFPR_RUN_PIGLIT=true
	;;
    --*)
	printf "Error: unknown option: $1\n" >&2
	usage
	exit 1
	;;
    -*)
	printf "Error: unknown option: $1\n" >&2
	usage
	exit 1
	;;
    *)
	printf "Error: unknown parameter: $1\n" >&2
	usage
	exit 1
	;;
    esac

    shift
done


# Paths ...
# ---------

CFPR_BASE_PATH="${CFPR_BASE_PATH:-$HOME/i965}"
CFPR_TEMP_PATH="${CFPR_TEMP_PATH:-$CFPR_BASE_PATH/cfpr-temp}"
CFPR_MESA_PATH="${CFPR_MESA_PATH:-$CFPR_BASE_PATH/mesa.git}"
CFPR_VK_GL_CTS_PATH="${CFPR_VK_GL_CTS_PATH:-$CFPR_BASE_PATH/vk-gl-cts.git}"
CFPR_VK_LOADER_PATH="${CFPR_VK_LOADER_PATH:-$CFPR_BASE_PATH/LoaderAndValidationLayers.git}"
# PATH where to place the piglit results
CFPR_PIGLIT_RESULTS_DIR="${CFPR_PIGLIT_RESULTS_DIR:-$CFPR_BASE_PATH/piglit-results}"


# merge-base run?
# ---------------

CFPR_MERGE_BASE_RUN="${CFPR_MERGE_BASE_RUN:-false}"


# What tests to run?
# ------------------

CFPR_RUN_VK_CTS="${CFPR_RUN_VK_CTS:-false}"
CFPR_RUN_GL_CTS="${CFPR_RUN_GL_CTS:-false}"
CFPR_RUN_PIGLIT="${CFPR_RUN_PIGLIT:-false}"


# Cleaning?
# ---------

CFPR_CLEAN="${CFPR_CLEAN:-true}"


# Force clean
# ------------

CFPR_FORCE_CLEAN="${CFPR_FORCE_CLEAN:-false}"

if $CFPR_FORCE_CLEAN; then
    clean_mesa
    clean_piglit
    clean_vk_gl_cts
    printf "%s\n" "" "rm -Ir $CFPR_TEMP_PATH" ""
    rm -Ir "$CFPR_TEMP_PATH"

    exit 0
fi


# Verbosity level
# ---------------

CFPR_VERBOSITY="${CFPR_VERBOSITY:-normal}"

check_verbosity "$CFPR_VERBOSITY"
if [ $? -ne 0 ]; then
    exit 13
fi


# Sanity check
# ------------

sanity_check "$CFPR_MESA_BRANCH" "$CFPR_VK_GL_CTS_BRANCH"
if [ $? -ne 0 ]; then
    exit 2
fi

apply_verbosity "$CFPR_VERBOSITY"

xhost +

run_tests

exit $?
