#!/bin/bash
# OCR-D task to be run as OCR script step by Kitodo.Production
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
# - ACTIVEMQ: host name and port of ActiveMQ server listening to result status
# assumptions:
# - controller has same network share /data as manager (no transfer necessary)
# - workflow file is preinstalled
# - scans are in process subdirectory 'images'
# - text results should reside in subdir 'ocr/alto'
# To be called (after copying data to 3.) via manager, e.g.:
#     ssh -Tn -p 9022 ocrd@ocrd-manager for_production.sh 501543 3 /home/goobi/work/daten/501543 deu Fraktur

set -eu
set -o pipefail

source ocr.sh

ocr_init $@

# run the workflow script on the controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
	ocr_process
	
	post_process # specific post processing for Kitodo.Production
	
) >/dev/null 2>&1 & # without output redirect, ssh will not close the connection upon exit, cf. #9

ocr_exit


post_process () {
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
}
