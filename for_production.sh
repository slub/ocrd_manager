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

init $@

# run the workflow script on the controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
	# TODO: copy the data explicitly from manager to controller here
    # e.g. `rsync -avr "$WORKDIR" --port $CONTROLLERPORT ocrd@$CONTROLLERHOST:/data`

	ocrd_controller_exec ocrd_import_workdir ocrd_process_workflow

	# TODO: copy the results back here
    # e.g. `rsync -avr --port $CONTROLLERPORT ocrd@$CONTROLLERHOST:/data/"$WORKDIR" "$WORKDIR"`
	
	post_process_validate_workdir
	
	post_process_provide_results
	
	post_process_activemq_exec
	
) >/dev/null 2>&1 & # without output redirect, ssh will not close the connection upon exit, cf. #9

close
