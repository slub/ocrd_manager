#!/bin/bash
# OCR-D task to be run as OCR script step by Kitodo.Presentation
# To be called (after copying METS file) via Manager, e.g.:
#     ssh -Tn -p 9022 ocrd@ocrd-manager for_presentation.sh \
#                                       --img-grp ORIGINAL --ocr-grp FULLTEXT \
#                                       --pages PHYS_0010..PHYS_0999 --workflow myocr.sh \
#                                       /home/goobi/work/daten/501543/mets.xml
# full CLI options: see --help

set -Eeu
set -o pipefail

source ocrd_lib.sh

init "$@"

# run the workflow script on the Controller non-interactively and log its output locally
# subsequently validate and postprocess the results
# do all this in a subshell in the background, so we can return immediately
(
  init_task

  pre_clone_to_workdir

  pre_sync_workdir

  ocrd_exec ocrd_enter_workdir ocrd_validate_workflow ocrd_process_workflow

  post_sync_workdir

  post_validate_workdir

  post_process_to_mets

  close_task

) |& tee -a $WORKDIR/ocrd.log | logger -p user.info -t $TASK &>/dev/null & # without output redirect, ssh will not close the connection upon exit, cf. #9

close
