#!/bin/bash
# OCR-D utils for ocr processing

set -eu
set -o pipefail

TASK=$(basename $0)

# initialize variables, create ord-d work directory and exit if something is missing
# args:
# 1. process ID
# 2. task ID
# 3. process dir path
# 4. language
# 5. script
# 6. async (default true)
# 7. workflow name (default preinstalled ocr-workflow-default.sh)
# 8. images dir path under process dir(default images)
# vars:
# - CONTROLLER: host name and port of ocrd_controller for processing
init () {    
    logger -p user.info -t $TASK "ocr_init initialize variables and directory structure"
    PROC_ID=$1
    TASK_ID=$2
    PROCDIR="$3"
    LANGUAGE="$4"
    SCRIPT="$5"
    ASYNC=${6:-true}    
    WORKFLOW="${7:-ocr-workflow-default.sh}"
    PROCIMAGEDIR="${8:-images}"

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

    WORKDIR=ocr-d/"$PROCDIR" # will use other mount-point than /data soon
    mkdir -p $(dirname "$WORKDIR")
}

# parse shell script notation into tasks syntax
ocrd_format_workflow () {
    cat "$WORKFLOW" | sed '/^[ ]*#/d;s/#.*//;s/"/\\"/g;s/^/"/;s/$/"/' | tr '\n\r' '  '
}

# ocrd import from workdir
ocrd_import_workdir () {
    echo "cd '$WORKDIR'"
    echo "ocrd-import -i"
}

ocrd_process_workflow () {
    echo -n "ocrd process "
    ocrd_format_workflow
}

# execute commands via ssh by the controller
ocrd_exec () {
    logger -p user.info -t $TASK "execute commands via ssh by the controller"
    {
        echo "set -e"
        for param in "$@"
        do
            $param
        done
    } | ssh -T -p "${CONTROLLERPORT}" ocrd@${CONTROLLERHOST} 2>&1 | logger -p user.info -t $TASK
}

pre_process_to_workdir () {
    # copy the data from the process directory controlled by production
    # to the transient directory controlled by the manager
    # (currently the same share, but will be distinct volumes;
    #  so the admin can decide to either mount distinct shares,
    #  which means the images will have to be physically copied,
    #  or the same share twice, which means zero-cost copying).
    cp -vr --reflink=auto "$PROCDIR/$PROCIMAGEDIR" "$WORKDIR" | logger -p user.info -t $TASK
}

pre_process_validate_workflow () {
    echo -n "ocrd validate tasks --workspace . "
    ocrd_format_workflow
}

post_process_validate_workdir () {
    ocrd workspace -d "$WORKDIR" validate -s mets_unique_identifier -s mets_file_group_names -s pixel_density
}

post_process_to_ocrdir () {
    # use last fileGrp as single result
    ocrgrp=$(ocrd workspace -d "$WORKDIR" list-group | tail -1)
    # map and copy to Kitodo filename conventions
    mkdir -p "$PROCDIR/ocr/alto"
    ocrd workspace -d "$WORKDIR" find -G $ocrgrp -k pageId -k local_filename | \
        { i=0; while read page path; do
                   # FIXME: use the same basename as the input,
                   # i.e. basename-pageId mapping instead of counting from 1
                   let i+=1 || true
                   basename=$(printf "%08d\n" $i)
                   extension=${path##*.}
                   cp -v "$WORKDIR/$path" "$PROCDIR/ocr/alto/$basename.$extension" | logger -p user.info -t $TASK
               done;
        }
}

activemq_close_task () {
    if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT"; then
        java -Dlog4j2.configurationFile=$ACTIVEMQ_CLIENT_LOG4J2 -jar "$ACTIVEMQ_CLIENT" "tcp://$ACTIVEMQ?closeAsync=false" "KitodoProduction.FinalizeStep.Queue" $TASK_ID $PROC_ID
    fi
}

# exit in async or sync mode
close () {
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
