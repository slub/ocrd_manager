#!/bin/bash
# OCR-D utils for ocr processing

set -eu
set -o pipefail

TASK=$(basename $0)

# initialize variables, create ord-d work directory and exit if something is missing
# args:
# 1. process ID
# 2. task ID
# 3. directory path
# 4. language
# 5. script
# 6. async (default true)
# 7. workflow name (default preinstalled ocr-workflow-default.sh)
# vars:
# - CONTROLLER: host name and port of ocrd_controller for processing
ocr_init () {	
	logger -p user.info -t $TASK "ocr_init initialize variables and structure"
	PROC_ID=$1
	TASK_ID=$2
	PROCDIR="$3"
	LANGUAGE="$4"
	SCRIPT="$5"
	ASYNC=${$6:true}	
	WORKFLOW="${7:-ocr-workflow-default.sh}"

	logger -p user.notice -t $TASK "running with $* CONTROLLER=$CONTROLLER"
	cd /data

	if ! test -d "$PROCDIR"; then
		logger -p user.error -t $TASK "invalid process directory '$PROCDIR'"
		exit 2
	fi
	WORKFLOWFILE="$PROCDIR/ocr-workflow.sh"
	if test -f "$WORKFLOWFILE"; then
	  WORKFLOW=$(realpath "$WORKFLOWFILE")
	else
	  WORKFLOW=$(command -v "$WORKFLOW" || realpath "$WORKFLOW")
		if ! test -f "$WORKFLOW"; then
			logger -p user.error -t $TASK "invalid workflow '$WORKFLOW'"
			exit 3
		fi
	fi
	if test -z "$CONTROLLER" -o "$CONTROLLER" = "${CONTROLLER#*:}"; then
		logger -p user.error -t $TASK "envvar CONTROLLER='$CONTROLLER' must contain host:port"
		exit 4
	fi
	CONTROLLERHOST=${CONTROLLER%:*}
	CONTROLLERPORT=${CONTROLLER#*:}
	
	# copy the data from the process directory controlled by production
	# to the transient directory controlled by the manager
	# (currently the same share, but will be distinct volumes;
	#  so the admin can decide to either mount distinct shares,
	#  which means the images will have to be physically copied,
	#  or the same share twice, which means zero-cost copying).
	WORKDIR=ocr-d/"$PROCDIR" # will use other mount-point than /data soon
	mkdir -p $(dirname "$WORKDIR")
	cp -vr --reflink=auto "$PROCDIR/images" "$WORKDIR" | logger -p user.info -t $TASK
}

# processing data via ssh by the controller
ocr_process () {
	logger -p user.info -t $TASK "ocr_process processing data via ssh by the controller"
    # TODO: copy the data explicitly from manager to controller here
    # e.g. `rsync -avr "$WORKDIR" --port $CONTROLLERPORT ocrd@$CONTROLLERHOST:/data`
    {
        echo "set -e"
        echo "cd '$WORKDIR'"
        echo "ocrd-import -i"
        echo -n "ocrd process "
        cat "$WORKFLOW" | sed '/^[ ]*#/d;s/#.*//;s/"/\\"/g;s/^/"/;s/$/"/' | tr '\n\r' '  '
    } | ssh -T -p "${CONTROLLERPORT}" ocrd@${CONTROLLERHOST} 2>&1 | logger -p user.info -t $TASK
    # TODO: copy the results back here
    # e.g. `rsync -avr --port $CONTROLLERPORT ocrd@$CONTROLLERHOST:/data/"$WORKDIR" "$WORKDIR"`
}

# exit in async or sync mode
ocr_exit () {
	if test "$ASYNC" = true; then
		logger -p user.info -t $TASK "ocr_exit in async mode - immediate termination of the script"
		# fail so Kitodo will listen to the actual time the job is done via ActiveMQ
		exit 1
	else
		# become synchronous again
		logger -p user.info -t $TASK "ocr_exit in sync mode - wait until the processing is completed"
		wait $!
	fi
}
