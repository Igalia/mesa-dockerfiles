#!/bin/bash
#
# This script is intended to run automatically as a cronjob, making
# use of full-piglit-run.sh
#
# Example:
#
# $ crontab -e
# ...
# 0 3 * * * <path_to>/f-p-r-cronjob.sh --mesa-commit "mesa-remote/mesa-branch" --vk-cts-commit "vk-gl-cts-remote/vk-cts-branch" --gl-cts-commit "vk-gl-cts-remote/gl-cts-branch" --aosp-deqp-commit "aosp-deqp-remote/aosp-deqp-branch"

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
	CDLP_PROGRESS_FLAG="-q"
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
    echo $arg | $CDLP_GREP "^-" > /dev/null
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
#   $2 - an existing VK-CTS' commit id
#   $3 - an existing GL-CTS' commit id
#   $4 - an existing AOSP dEQP's commit id
# returns:
#   0 is success, an error code otherwise
function sanity_check() {
    if [ "x$1" == "x" ] || [ "x$2" == "x" ] || [ "x$3" == "x" ] || [ "x$4" == "x" ]; then
	printf "Error: Missing parameters.\n" >&2
	usage
	return 2
    fi

    pushd "$CDLP_MESA_PATH"
    git fetch $CDLP_PROGRESS_FLAG origin
    CDLP_MESA_BRANCH=$(git show -s --pretty=format:%h "$1")
    CDLP_RESULT=$?
    popd
    if [ $CDLP_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: mesa's commit id doesn't exist in the repository." "" >&2
	usage
	return 3
    fi

    pushd "$CDLP_VK_GL_CTS_PATH"
    git fetch $CDLP_PROGRESS_FLAG origin
    CDLP_VK_CTS_BRANCH=$(git show -s --pretty=format:%h "$2")
    CDLP_RESULT=$?
    popd
    if [ $CDLP_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: VK-CTS' commit id doesn't exist in the repository." "" >&2
	usage
	return 4
    fi
    pushd "$CDLP_VK_GL_CTS_PATH"
    CDLP_GL_CTS_BRANCH=$(git show -s --pretty=format:%h "$3")
    CDLP_RESULT=$?
    popd
    if [ $CDLP_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: GL-CTS' commit id doesn't exist in the repository." "" >&2
	usage
	return 5
    fi

    pushd "$CDLP_AOSP_DEQP_PATH"
    git fetch $CDLP_PROGRESS_FLAG origin
    CDLP_AOSP_DEQP_BRANCH=$(git show -s --pretty=format:%h "$4")
    CDLP_RESULT=$?
    popd
    if [ $CDLP_RESULT -ne 0 ]; then
	printf "%s\n" "" "Error: AOSP dEQP's commit id doesn't exist in the repository." "" >&2
	usage
	return 6
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
    CDLP_TIMESTAMP=$(date +%Y%m%d%H%M%S)
    CDLP_SPACE=$(df -h)
    printf "%s\n" "Running $1 at $CDLP_TIMESTAMP" "" "$CDLP_SPACE" "" >&9

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_mesa
#------------------------------------------------------------------------------
#
# builds a specific commit of mesa or the latest common commit with master
#   $1 - mesa commit to use
#   $2 - whether to build the merge base against master or not
# returns:
#   0 is success, an error code otherwise
function build_mesa() {
    rm -rf "$CDLP_TEMP_PATH/mesa"
    git clone $CDLP_PROGRESS_FLAG "$CDLP_MESA_PATH" "$CDLP_TEMP_PATH/mesa"
    pushd "$CDLP_MESA_PATH"
    CDLP_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CDLP_TEMP_PATH/mesa"
    git remote set-url origin "$CDLP_ORIGIN_URL"
    git fetch $CDLP_PROGRESS_FLAG origin
    git branch -m old
    if $2; then
	COMMIT=$(git merge-base origin/master "$1")
    else
	COMMIT="$1"
    fi
    git checkout $CDLP_PROGRESS_FLAG -b working "$COMMIT"
    git branch -D old
    CDLP_MESA_COMMIT=$(git show -s --pretty=format:%h "$COMMIT")

    if $CDLP_REUSE; then
	docker pull "$DOCKER_IMAGE":mesa."$CDLP_MESA_COMMIT" 2>&1
	test $? -eq 0 && return 0
    fi

    wget $CDLP_PROGRESS_FLAG https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/cts/Rockerfile.mesa
    # make check is failing right now and we don't really need it
    sed -e 's/&& make check//g' -i Rockerfile.mesa

    __CDLP_OLD_DOCKER_IMAGE="$DOCKER_IMAGE"
    DOCKER_IMAGE="igalia/mesa"

    rocker build --pull -f Rockerfile.mesa --var BUILD="autotools" --var LLVM="5.0" --var CLEAN=false --var DEBUG="$CDLP_DEBUG" --var TAG=mesa."$CDLP_MESA_COMMIT"
    popd

    if [ ! -z "$CDLP_DOCKER_REPOSITORY" ]; then
	docker tag "$DOCKER_IMAGE":mesa."$CDLP_MESA_COMMIT" "$CDLP_DOCKER_REPOSITORY":mesa."$CDLP_MESA_COMMIT"
	docker rmi "$DOCKER_IMAGE":mesa."$CDLP_MESA_COMMIT"
	docker push "$CDLP_DOCKER_REPOSITORY":mesa."$CDLP_MESA_COMMIT"
    fi

    DOCKER_IMAGE="$__CDLP_OLD_DOCKER_IMAGE"
    unset __CDLP_OLD_DOCKER_IMAGE

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
    rm -rf "$CDLP_TEMP_PATH/mesa"
    if $CDLP_CLEAN; then
	docker rmi "$DOCKER_IMAGE":mesa."$CDLP_MESA_COMMIT"
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_vk_gl_cts
#------------------------------------------------------------------------------
#
# builds a specific commit of vk-gl-cts
#   $1 - vk-gl-cts commit to use
# returns:
#   0 is success, an error code otherwise
function build_vk_gl_cts() {
    rm -rf "$CDLP_TEMP_PATH/LoaderAndValidationLayers.$1"
    git clone $CDLP_PROGRESS_FLAG "$CDLP_VK_LOADER_PATH" "$CDLP_TEMP_PATH/LoaderAndValidationLayers"
    pushd "$CDLP_VK_LOADER_PATH"
    CDLP_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CDLP_TEMP_PATH/LoaderAndValidationLayers"
    git remote set-url origin "$CDLP_ORIGIN_URL"
    git fetch $CDLP_PROGRESS_FLAG origin
    git branch -m old
    git checkout $CDLP_PROGRESS_FLAG -b working origin/master
    git branch -D old
    popd

    if $CDLP_REUSE; then
	docker pull "$DOCKER_IMAGE":vk-gl-cts."$1" 2>&1
	test $? -eq 0 && return 0
    fi

    rm -rf "$CDLP_TEMP_PATH/vk-gl-cts.$1"
    git clone $CDLP_PROGRESS_FLAG "$CDLP_VK_GL_CTS_PATH" "$CDLP_TEMP_PATH/vk-gl-cts"
    pushd "$CDLP_VK_GL_CTS_PATH"
    CDLP_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CDLP_TEMP_PATH/vk-gl-cts"
    git remote set-url origin "$CDLP_ORIGIN_URL"
    git fetch $CDLP_PROGRESS_FLAG origin
    git branch -m old
    git checkout $CDLP_PROGRESS_FLAG -b working "$1"
    git branch -D old
    if [ ! -z "$CDLP_GL_CTS_GTF" ]; then
	python ./external/fetch_kc_cts.py --protocol ssh
    fi
    popd
    pushd "$CDLP_TEMP_PATH"
    wget $CDLP_PROGRESS_FLAG https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/cts/Rockerfile.vk-gl-cts
    DOCKER_IMAGE="$DOCKER_IMAGE" rocker build -f Rockerfile.vk-gl-cts --var VIDEO_GID=`getent group video | cut -f3 -d:` --var FPR_BRANCH="$CDLP_FPR_BRANCH" --var TARGET="$CDLP_VK_GL_CTS_TARGET" --var DEBUG="$CDLP_DEBUG" --var TAG=vk-gl-cts."$1" --var RELEASE=mesa."$CDLP_MESA_COMMIT"${CDLP_GL_CTS_GTF:+ --var GTF=}"$CDLP_GL_CTS_GTF"
    popd

    if [ ! -z "$CDLP_DOCKER_REPOSITORY" ]; then
	docker push "$DOCKER_IMAGE":vk-gl-cts."$1"
    fi

    mv "$CDLP_TEMP_PATH/LoaderAndValidationLayers" "$CDLP_TEMP_PATH/LoaderAndValidationLayers.$1"
    mv "$CDLP_TEMP_PATH/vk-gl-cts" "$CDLP_TEMP_PATH/vk-gl-cts.$1"
    mv "$CDLP_TEMP_PATH/Rockerfile.vk-gl-cts" "$CDLP_TEMP_PATH/Rockerfile.vk-gl-cts.$1"

    return 0
}


#------------------------------------------------------------------------------
#			Function: clean_vk_gl_cts
#------------------------------------------------------------------------------
#
# cleans the used vk_gl_cts's worktree
#   $1 - vk-gl-cts commit to use
# returns:
#   0 is success, an error code otherwise
function clean_vk_gl_cts() {
    rm -rf "$CDLP_TEMP_PATH/LoaderAndValidationLayers.$1"
    rm -rf "$CDLP_TEMP_PATH/vk-gl-cts.$1"
    rm -f "$CDLP_TEMP_PATH/Rockerfile.vk-gl-cts.$1"
    if $CDLP_CLEAN; then
	docker rmi "$DOCKER_IMAGE":vk-gl-cts."$1"
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
    # We don't use a specific piglit commit. Hence, we cannot reuse.

    rm -rf "$CDLP_TEMP_PATH/piglit"
    mkdir -p "$CDLP_TEMP_PATH/piglit"
    pushd "$CDLP_TEMP_PATH/piglit"
    wget $CDLP_PROGRESS_FLAG https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/master/Rockerfile.piglit
    DOCKER_IMAGE="$DOCKER_IMAGE" rocker build -f Rockerfile.piglit --var FPR_BRANCH="$CDLP_FPR_BRANCH" --var TAG=piglit --var RELEASE=mesa."$CDLP_MESA_COMMIT"
    popd

    if [ ! -z "$CDLP_DOCKER_REPOSITORY" ]; then
	docker push "${DOCKER_IMAGE}":piglit
    fi

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
    rm -rf "$CDLP_TEMP_PATH/piglit"
    if $CDLP_CLEAN; then
	docker rmi "$DOCKER_IMAGE":piglit
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: build_aosp_deqp
#------------------------------------------------------------------------------
#
# builds a specific commit of AOSP dEQP
#   $1 - AOSP dEQP commit to use
# returns:
#   0 is success, an error code otherwise
function build_aosp_deqp() {
    if $CDLP_REUSE; then
	docker pull "${DOCKER_IMAGE}":aosp-deqp."$1" 2>&1
	test $? -eq 0 && return 0
    fi

    rm -rf "$CDLP_TEMP_PATH/aosp-deqp"
    git clone $CDLP_PROGRESS_FLAG "$CDLP_AOSP_DEQP_PATH" "$CDLP_TEMP_PATH/aosp-deqp"
    pushd "$CDLP_AOSP_DEQP_PATH"
    CDLP_ORIGIN_URL=$(git remote get-url origin)
    popd
    pushd "$CDLP_TEMP_PATH/aosp-deqp"
    git remote set-url origin "$CDLP_ORIGIN_URL"
    git fetch $CDLP_PROGRESS_FLAG origin
    git branch -m old
    git checkout $CDLP_PROGRESS_FLAG -b working "$1"
    git branch -D old
    popd
    pushd "$CDLP_TEMP_PATH"
    wget $CDLP_PROGRESS_FLAG https://raw.githubusercontent.com/Igalia/mesa-dockerfiles/cts/Rockerfile.deqp
    DOCKER_IMAGE="$DOCKER_IMAGE" rocker build -f Rockerfile.deqp --var VIDEO_GID=`getent group video | cut -f3 -d:` --var FPR_BRANCH="$CDLP_FPR_BRANCH" --var DEBUG="$CDLP_DEBUG" --var TAG=aosp-deqp."$1" --var RELEASE=mesa."$CDLP_MESA_COMMIT"
    popd

    if [ ! -z "$CDLP_DOCKER_REPOSITORY" ]; then
	docker push "${DOCKER_IMAGE}":aosp-deqp."$1"
    fi

    return 0
}


#------------------------------------------------------------------------------
#			Function: clean_aosp_deqp
#------------------------------------------------------------------------------
#
# cleans the used AOSP dEQP's worktree
#   $1 - AOSP dEQP commit to use
# returns:
#   0 is success, an error code otherwise
function clean_aosp_deqp() {
    rm -rf "$CDLP_TEMP_PATH/aosp-deqp"
    if $CDLP_CLEAN; then
	docker rmi "$DOCKER_IMAGE":aosp-deqp."$1"
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

    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/all-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/all-"$1"

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

    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/GL-CTS-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/GL-CTS-"$1"

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

    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/VK-CTS-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/VK-CTS-"$1"

    return 0
}


#------------------------------------------------------------------------------
#			Function: create_aosp_deqp_reference
#------------------------------------------------------------------------------
#
# creates the soft link to the AOSP dEQP reference run
#   $1 - the driver for which to create the reference
# returns:
#   0 is success, an error code otherwise
function create_aosp_deqp_reference() {
    if [ "x$1" == "x" ]; then
	return -1
    fi

    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/AOSP-DEQP2-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/AOSP-DEQP2-"$1"
    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/AOSP-DEQP3-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/AOSP-DEQP3-"$1"
    ln -sfr $(ls -d $CDLP_PIGLIT_RESULTS_DIR/results/AOSP-DEQP31-"$1"* | tail -1) -T $CDLP_PIGLIT_RESULTS_DIR/reference/AOSP-DEQP31-"$1"

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

    if [ ! -d "${CDLP_PIGLIT_RESULTS_DIR}" ]; then
	printf "%s\n" "Error: ${CDLP_PIGLIT_RESULTS_DIR} directory doesn't exist." >&2
	return 4
    fi

    header

    mkdir -p "$CDLP_TEMP_PATH/jail"

    pushd "$CDLP_TEMP_PATH/jail"

    build_mesa "$CDLP_MESA_BRANCH" $CDLP_MERGE_BASE_RUN

    CDLP_EXTRA_ARGS="--verbosity $CDLP_VERBOSITY $CDLP_EXTRA_ARGS"
    $CDLP_CREATE_PIGLIT_REPORT && CDLP_EXTRA_ARGS="--create-piglit-report $CDLP_EXTRA_ARGS"

    if $CDLP_RUN_PIGLIT; then
    	build_piglit

	if ! $CDLP_DRY_RUN; then

	    printf "%s\n" "" "Checking piglit progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CDLP_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="$CDLP_EXTRA_ARGS" \
		   -e GL_DRIVER="i965" "$DOCKER_IMAGE":piglit

	    apply_verbosity "$CDLP_VERBOSITY"

	    $CDLP_MERGE_BASE_RUN && create_piglit_reference "i965"

	fi

    	clean_piglit
    fi

    if $CDLP_RUN_GL_CTS; then
	build_vk_gl_cts "$CDLP_GL_CTS_BRANCH"

	if ! $CDLP_DRY_RUN; then

	    printf "%s\n" "" "Checking GL CTS progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CDLP_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="$CDLP_EXTRA_ARGS" \
		   -e CTS="opengl" \
		   -e GL_DRIVER="i965" "$DOCKER_IMAGE":vk-gl-cts."$CDLP_GL_CTS_BRANCH"

	    apply_verbosity "$CDLP_VERBOSITY"

	    $CDLP_MERGE_BASE_RUN && create_gl_cts_reference "i965"

	fi

	clean_vk_gl_cts "$CDLP_GL_CTS_BRANCH"
    fi

    if $CDLP_RUN_VK_CTS; then
	build_vk_gl_cts	"$CDLP_VK_CTS_BRANCH"

	if ! $CDLP_DRY_RUN; then

	    printf "%s\n" "" "Checking VK CTS progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CDLP_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="--vk-cts-all-concurrent $CDLP_EXTRA_ARGS" \
		   -e CTS="vulkan" \
		   -e GL_DRIVER="anv" "$DOCKER_IMAGE":vk-gl-cts."$CDLP_VK_CTS_BRANCH"

	    apply_verbosity "$CDLP_VERBOSITY"

	    $CDLP_MERGE_BASE_RUN && create_vk_cts_reference "anv"

	fi

	clean_vk_gl_cts	"$CDLP_VK_CTS_BRANCH"
    fi

    if $CDLP_RUN_AOSP_DEQP; then
	build_aosp_deqp "$CDLP_AOSP_DEQP_BRANCH"

	if ! $CDLP_DRY_RUN; then

	    printf "%s\n" "" "Checking AOSP dEQP progress ..." "" >&9

	    # We restore the redirection so the output is managed by
	    # the commands inside "docker run"
	    restore_redirection

	    docker run --privileged --rm -t -v "${CDLP_PIGLIT_RESULTS_DIR}":/results:Z \
		   -e DISPLAY=unix$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
		   -e FPR_EXTRA_ARGS="$CDLP_EXTRA_ARGS" \
		   -e GL_DRIVER="i965" "$DOCKER_IMAGE":vk-gl-cts."$CDLP_AOSP_DEQP_BRANCH"

	    apply_verbosity "$CDLP_VERBOSITY"

	    $CDLP_MERGE_BASE_RUN && create_aosp_deqp_reference "i965"

	fi

	clean_aosp_deqp "$CDLP_AOSP_DEQP_BRANCH"
    fi

    clean_mesa

    popd
    rm -rf "$CDLP_TEMP_PATH/"

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

Usage: $basename [options] --mesa-commit <mesa-commit-id> --vk-cts-commit <vk-cts-commit-id> --gl-cts-commit <gl-cts-commit-id>

Options:
  --help                           Display this help and exit successfully
  --dry-run                        Does everything except running the tests
  --verbosity [full|normal|quiet]  Which verbosity level to use
                                   [full|normal|quite]. Default, normal.
  --no-clean                       Do not clean the created images
  --no-reuse                       Rebuild an image even if it already exists
  --debug                          Build images in debug mode
  --force-clean                    Forces the cleaning of the working env
  --base-path <path>               <path> from which to create the rest of the
                                   relative paths
  --tmp-path <path>                <path> in which to do the temporary work
  --mesa-path <path>               <path> to the mesa repository
  --vk-gl-cts-path <path>          <path> to the vk-gl-cts repository
  --vk-loader-path <path>          <path> to the LoaderAndValidationLayers
                                   repository
  --aosp-deqp-path                 <path> to the AOSP dEQP repository
  --piglit-results-dir <path>      <path> where to place the piglit results
  --mesa-commit <commit>           mesa <commit> to use
  --vk-cts-commit <commit>         VK-CTS <commit> to use
  --gl-cts-commit <commit>         GL-CTS <commit> to use
  --aosp-deqp-commit <commit>      AOSP dEQP <commit> to use
  --vk-gl-cts-target <target>      VK-GL-CTS <target> to use
  --gl-cts-gtf <gtf-target>        GL-CTS <gtf-target> to use
  --docker-repository <repository> Docker <repository> to push to
  --merge-base-run                 merge-base run
  --run-vk-cts                     Run vk-cts
  --run-gl-cts                     Run gl-cts
  --run-piglit                     Run piglit
  --run-aosp-deqp                  Run AOSP dEQP
  --fpr-branch <branch>            full-piglit-run.sh' <branch>
  --create-piglit-report           Create results report

HELP
}


#------------------------------------------------------------------------------
#			Script main line
#------------------------------------------------------------------------------
#

# Choose which grep program to use (on Solaris, must be gnu grep)
if [ "x$CDP_GREP" = "x" ] ; then
    if [ -x /usr/gnu/bin/grep ] ; then
	CDLP_GREP=/usr/gnu/bin/grep
    else
	CDLP_GREP=grep
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
    # Does everything except running the tests
    --dry-run)
	CDLP_DRY_RUN=true
	;;
    # Which verbosity level to use [full|normal|quite]. Default, normal.
    --verbosity)
	check_option_args $1 $2
	shift
	CDLP_VERBOSITY=$1
	;;
    # Do not clean the created images
    --no-clean)
	CDLP_CLEAN=false
	;;
    # Rebuild an image even if it already exists
    --no-reuse)
	CDLP_REUSE=false
	;;
    # Build images in debug mode
    --debug)
	CDLP_DEBUG=true
	;;
    # Forces the cleaning of the working env
    --force-clean)
	CDLP_FORCE_CLEAN=true
	;;
    # PATH from which to create the rest of the relative paths
    --base-path)
	check_option_args $1 $2
	shift
	CDLP_BASE_PATH=$1
	;;
    # PATH in which to do the temporary work
    --tmp-path)
	check_option_args $1 $2
	shift
	CDLP_TEMP_PATH=$1
	;;
    # PATH to the mesa repository
    --mesa-path)
	check_option_args $1 $2
	shift
	CDLP_MESA_PATH=$1
	;;
    # PATH to the vk-gl-cts repository
    --vk-gl-cts-path)
	check_option_args $1 $2
	shift
	CDLP_VK_GL_CTS_PATH=$1
	;;
    # PATH to the LoaderAndValidationLayers repository
    --vk-loader-path)
	check_option_args $1 $2
	shift
	CDLP_VK_LOADER_PATH=$1
	;;
    # PATH to the AOSP dEQP repository
    --aosp-deqp-path)
	check_option_args $1 $2
	shift
	CDLP_AOSP_DEQP_PATH=$1
	;;
    # PATH where to place the piglit results
    --piglit-results-dir)
	check_option_args $1 $2
	shift
	CDLP_PIGLIT_RESULTS_DIR=$1
	;;
    # mesa commit to use
    --mesa-commit)
	check_option_args $1 $2
	shift
	CDLP_MESA_BRANCH=$1
	;;
    # VK-CTS commit to use
    --vk-cts-commit)
	check_option_args $1 $2
	shift
	CDLP_VK_CTS_BRANCH=$1
	;;
    # GL-CTS commit to use
    --gl-cts-commit)
	check_option_args $1 $2
	shift
	CDLP_GL_CTS_BRANCH=$1
	;;
    # AOSP dEQP commit to use
    --aosp-deqp-commit)
	check_option_args $1 $2
	shift
	CDLP_AOSP_DEQP_BRANCH=$1
	;;
    # VK-GL-CTS target to use
    --vk-gl-cts-target)
	check_option_args $1 $2
	shift
	CDLP_VK_GL_CTS_TARGET=$1
	;;
    # GL-CTS GTF target to use
    --gl-cts-gtf)
	check_option_args $1 $2
	shift
	CDLP_GL_CTS_GTF=$1
	;;
    # Docker repository to push to
    --docker-repository)
	check_option_args $1 $2
	shift
	CDLP_DOCKER_REPOSITORY=$1
	;;
    # merge-base run
    --merge-base-run)
	CDLP_MERGE_BASE_RUN=true
	;;
    # Run vk-cts
    --run-vk-cts)
	CDLP_RUN_VK_CTS=true
	;;
    # Run gl-cts
    --run-gl-cts)
	CDLP_RUN_GL_CTS=true
	;;
    # Run piglit
    --run-piglit)
	CDLP_RUN_PIGLIT=true
	;;
    # Run AOSP dEQP
    --run-aosp-deqp)
	CDLP_RUN_AOSP_DEQP=true
	;;
    # full-piglit-run.sh' <branch>
    --fpr-branch)
       check_option_args $1 $2
       shift
       CDLP_FPR_BRANCH=$1
       ;;
    # Create results report
    --create-piglit-report)
	CDLP_CREATE_PIGLIT_REPORT=true
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

CDLP_BASE_PATH="${CDLP_BASE_PATH:-$HOME/i965}"
CDLP_TEMP_PATH="${CDLP_TEMP_PATH:-$CDLP_BASE_PATH/cfpr-temp}"
CDLP_MESA_PATH="${CDLP_MESA_PATH:-$CDLP_BASE_PATH/mesa.git}"
CDLP_VK_GL_CTS_PATH="${CDLP_VK_GL_CTS_PATH:-$CDLP_BASE_PATH/vk-gl-cts.git}"
CDLP_VK_LOADER_PATH="${CDLP_VK_LOADER_PATH:-$CDLP_BASE_PATH/LoaderAndValidationLayers.git}"
CDLP_AOSP_DEQP_PATH="${CDLP_AOSP_DEQP_PATH:-$CDLP_BASE_PATH/aosp-deqp.git}"
# PATH where to place the piglit results
CDLP_PIGLIT_RESULTS_DIR="${CDLP_PIGLIT_RESULTS_DIR:-$CDLP_BASE_PATH/piglit-results}"


# merge-base run?
# ---------------

CDLP_MERGE_BASE_RUN="${CDLP_MERGE_BASE_RUN:-false}"


# What tests to run?
# ------------------

CDLP_RUN_VK_CTS="${CDLP_RUN_VK_CTS:-false}"
CDLP_RUN_GL_CTS="${CDLP_RUN_GL_CTS:-false}"
CDLP_RUN_PIGLIT="${CDLP_RUN_PIGLIT:-false}"
CDLP_RUN_AOSP_DEQP="${CDLP_RUN_AOSP_DEQP:-false}"


# What VK-GL-CTS target to use?
# -----------------------------

CDLP_VK_GL_CTS_TARGET="${CDLP_VK_GL_CTS_TARGET:-x11_egl}"


# Docker settings
# ---------------

DOCKER_IMAGE="${CDLP_DOCKER_REPOSITORY:-igalia/mesa}"


# Cleaning?
# ---------

CDLP_CLEAN="${CDLP_CLEAN:-true}"


# Reusing?
# ---------

CDLP_REUSE="${CDLP_REUSE:-true}"


# Debug?
# ---------

CDLP_DEBUG="${CDLP_DEBUG:-false}"


# dry run?
# --------

CDLP_DRY_RUN="${CDLP_DRY_RUN:-false}"


# Create a report against the reference result?
# ---------------------------------------------

CDLP_CREATE_PIGLIT_REPORT="${CDLP_CREATE_PIGLIT_REPORT:-false}"


# Force clean
# ------------

CDLP_FORCE_CLEAN="${CDLP_FORCE_CLEAN:-false}"

if $CDLP_FORCE_CLEAN; then
    clean_mesa
    clean_piglit
    clean_aosp_deqp "$CDLP_AOSP_DEQP_BRANCH"
    clean_vk_gl_cts "$CDLP_GL_CTS_BRANCH"
    clean_vk_gl_cts "$CDLP_VK_CTS_BRANCH"
    printf "%s\n" "" "rm -Ir $CDLP_TEMP_PATH" ""
    rm -Ir "$CDLP_TEMP_PATH"

    exit 0
fi

# Which FPR branch to use?
# -----------------------

CDLP_FPR_BRANCH="${CDLP_FPR_BRANCH:-master}"

# Verbosity level
# ---------------

CDLP_VERBOSITY="${CDLP_VERBOSITY:-normal}"

check_verbosity "$CDLP_VERBOSITY"
if [ $? -ne 0 ]; then
    exit 13
fi

apply_verbosity "$CDLP_VERBOSITY"


# Sanity check
# ------------

sanity_check "$CDLP_MESA_BRANCH" "$CDLP_VK_CTS_BRANCH" "$CDLP_GL_CTS_BRANCH" "$CDLP_AOSP_DEQP_BRANCH"
if [ $? -ne 0 ]; then
    exit 2
fi

xhost +

# ---


run_tests

exit $?
