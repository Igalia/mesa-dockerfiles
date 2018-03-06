#!/bin/bash

export LC_ALL=C

PATH=${HOME}/.local/bin$(echo :$PATH | sed -e s@:${HOME}/.local/bin@@g)


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
	CTRI_PROGRESS_FLAG="-q"
    fi

    if [ "x$1" == "xquiet" ]; then
	exec 2>/dev/null
	exec 9>/dev/null
    fi
}

# Verbosity level
# ---------------

CTRI_VERBOSITY="${CTRI_VERBOSITY:-normal}"

check_verbosity "$CTRI_VERBOSITY"
if [ $? -ne 0 ]; then
    exit 13
fi

apply_verbosity "$CTRI_VERBOSITY"

# ---


pushd "$1"
git fetch  $CTRI_PROGRESS_FLAG origin
CTRI_REPO_BRANCH=$(git show -s --pretty=format:%h "$2")
CTRI_MESA_DOCKERFILES_PATH="$HOME/mesa-dockerfiles.git"
CTRI_RESULT=$?
popd
if [ $CTRI_RESULT -ne 0 ]; then
    printf "%s\n" "" "Error: $4's commit id doesn't exist in the repository." "" >&2
    exit 1
fi

CTRI_TAG="${2##*/}.cl.base"

docker pull "$3":"$4"."$CTRI_REPO_BRANCH"

pushd "$CTRI_MESA_DOCKERFILES_PATH"
DOCKER_IMAGE="$3" rocker build -f Rockerfile.cts --var TAG="$4"."$CTRI_TAG" --var RELEASE="$4"."$CTRI_REPO_BRANCH"
popd

docker push "$3":"$4"."$CTRI_TAG"
docker rmi "$3":"$4"."$CTRI_REPO_BRANCH"
