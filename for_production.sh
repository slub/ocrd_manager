#!/bin/bash
# OCR-D task to be run as OCR script step by Kitodo.Production
# args:
# 1. process ID
# 2. task ID
# 3. directory path
# 4. language
# 5. script
# 6. workflow name
# vars:
# - CONTROLLER: host name and port of ocrd_controller for processing
# - ACTIVEMQ: host name and port of ActiveMQ server listening to result status
# assumptions:
# - controller has same network share /data as manager (no transfer necessary)
# - workflow file is preinstalled
# - scans are in process subdirectory 'images'
# - text results should reside in subdir 'ocr/alto'
# To be called (after copying data to 3.) via manager, e.g.:
#     ssh -Tn -p 9022 ocrd@ocrd-manager for_production.sh 501543 3 /home/goobi/work/daten/501543 deu Fraktur ocr.sh

set -eu
set -o pipefail

TASK=$(basename $0)
PROC_ID=$1
TASK_ID=$2
PROCDIR="$3"
LANGUAGE="$4"
SCRIPT="$5"
WORKFLOW="${6:-ocr.sh}"

logger -p user.notice -t $TASK "running with $* CONTROLLER=$CONTROLLER"
cd /data

if ! test -d "$PROCDIR"; then
    logger -p user.error -t $TASK "invalid process directory '$PROCDIR'"
    exit 2
fi
WORKFLOW=$(command -v "$WORKFLOW" || realpath "$WORKFLOW")
if ! test -f "$WORKFLOW"; then
    logger -p user.error -t $TASK "invalid workflow '$WORKFLOW'"
    exit 3
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

# run the workflow script on the controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
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
    
    ocrd workspace -d "$WORKDIR" validate -s mets_unique_identifier -s mets_file_group_names -s pixel_density
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
    # signal SUCCESS via ActiveMQ
    if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT"; then
        java -Dlog4j2.configurationFile=$ACTIVEMQ_CLIENT_LOG4J2 -jar "$ACTIVEMQ_CLIENT" "tcp://$ACTIVEMQ?closeAsync=false" "KitodoProduction.FinalizeStep.Queue" $TASK_ID $PROC_ID
    fi
) >/dev/null 2>&1 & # without output redirect, ssh will not close the connection upon exit, cf. #9

if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT"; then
    logger -p user.info -t $TASK "async mode - exit and signal end of processing using active mq client"
    # fail so Kitodo will listen to the actual time the job is done via ActiveMQ
    exit 1
else
    # become synchronous again
	logger -p user.info -t $TASK "sync mode - wait for workflow, validation and postprocessing of process $PROC_ID"
    wait $!
fi
