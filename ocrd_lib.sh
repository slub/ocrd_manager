#!/bin/bash
# OCR-D utils for ocr processing

set -eu
set -o pipefail

TASK=$(basename $0)

logerr() {
  logger -p user.info -t $TASK "terminating with error \$?=$? from ${BASH_COMMAND} on line $(caller)"
}

stopbg() {
  logger -p user.crit -t $TASK "passing SIGKILL to child $!"
  # pass signal on to children
  kill -KILL $!
}

# initialize variables, create ord-d work directory and exit if something is missing
init() {
  trap logerr ERR
  trap stopbg INT TERM KILL
  
  PID=$$

  cd /data

  logger -p user.info -t $TASK "ocr_init initialize variables and directory structure"
  logger -p user.notice -t $TASK "running with $* CONTROLLER=${CONTROLLER:-} ACTIVEMQ=${ACTIVEMQ:-}"

  # to be defined by caller
  parse_args "$@"

  if ! test -d "$PROCESS_DIR"; then
    logger -p user.error -t $TASK "invalid input directory '$PROCESS_DIR'"
    exit 2
  fi

  WORKDIR=ocr-d/"$PROCESS_DIR" # use subdirectory of same volume so --reflink CoW still possible
  if ! mkdir -p "$WORKDIR"; then
    logger -p user.error -t $TASK "insufficient permissions on /data volume"
    exit 5
  fi
  # try to be unique here (to avoid clashes)
  REMOTEDIR="KitodoJob_${PID}_$(basename $PROCESS_DIR)"

  WORKFLOW=$(command -v "$WORKFLOW" || realpath "$WORKFLOW")
  if ! test -f "$WORKFLOW"; then
    logger -p user.error -t $TASK "invalid workflow '$WORKFLOW'"
    exit 3
  fi
  logger -p user.notice -t $TASK "using workflow '$WORKFLOW':"
  ocrd_format_workflow | logger -p user.notice -t $TASK
  if test "${WORKFLOW#/workflows/}" = "$WORKFLOW"; then
      cp -p "$WORKFLOW" "$WORKDIR/workflow.sh"
      WORKFLOW="$WORKDIR/workflow.sh"
  fi

  if test -z "$CONTROLLER" -o "$CONTROLLER" = "${CONTROLLER#*:}"; then
    logger -p user.error -t $TASK "envvar CONTROLLER='$CONTROLLER' must contain host:port"
    exit 4
  fi
  CONTROLLERHOST=${CONTROLLER%:*}
  CONTROLLERPORT=${CONTROLLER#*:}

  # create stats for monitor
  mkdir -p /run/lock/ocrd.jobs/
  {
    echo PID=$PID
    echo TIME_CREATED=$(date --rfc-3339=seconds)
    echo PROCESS_ID=$PROCESS_ID
    echo TASK_ID=$TASK_ID
    echo PROCESS_DIR=$PROCESS_DIR
    echo WORKDIR=$WORKDIR
    echo REMOTEDIR=$REMOTEDIR
    echo WORKFLOW=$WORKFLOW
    echo CONTROLLER=$CONTROLLER
  } > /run/lock/ocrd.jobs/$REMOTEDIR

}

logret() {
    sed -i "1s/PID=.*/RETVAL=$?/" /run/lock/ocrd.jobs/$REMOTEDIR
    sed -i "2a TIME_TERMINATED=$(date --rfc-3339=seconds)" /run/lock/ocrd.jobs/$REMOTEDIR
}

init_task() {
  trap logret EXIT
}

# parse shell script notation into tasks syntax
ocrd_format_workflow() {
  cat "$WORKFLOW" | sed '/^[ ]*#/d;s/#.*//;s/"/\\"/g;s/^/"/;s/$/"/' | tr '\n\r' '  '
  echo
}

# ocrd import from workdir
ocrd_import_workdir() {
  echo "echo \$\$ > $REMOTEDIR/ocrd.pid"
  echo "if test -f '$REMOTEDIR/mets.xml'; then OV=--overwrite; else OV=; ocrd-import -i '$REMOTEDIR'; fi"
  echo "cd '$REMOTEDIR'"
}

ocrd_enter_workdir() {
  echo "echo \$\$ > $REMOTEDIR/ocrd.pid"
  echo "if test -f '$REMOTEDIR/mets.xml'; then OV=--overwrite; else OV=; fi"
  echo "cd '$REMOTEDIR'"
}

ocrd_process_workflow() {
  echo -n 'ocrd process $OV '
  if test -n "${PAGES:-}"; then echo -n "-g $PAGES "; fi
  ocrd_format_workflow
}

# execute commands via ssh by the controller
ocrd_exec() {
  logger -p user.info -t $TASK "execute $# commands via SSH by the controller"
  {
    echo "set -Ee"
    for param in "$@"; do
      $param
    done
  } | ssh -T -p "${CONTROLLERPORT}" ocrd@${CONTROLLERHOST} 2>&1
}

pre_process_to_workdir() {
  # copy the data from the process directory controlled by Kitodo.Production
  # to the transient directory controlled by the Manager
  # (currently the same share, but will be distinct volumes;
  #  so the admin can decide to either mount distinct shares,
  #  which means the images will have to be physically copied,
  #  or the same share twice, which means zero-cost copying).
  if test -f "$WORKDIR/mets.xml"; then
    # already a workspace - repeated run
    rsync -T /tmp -av "$PROCESS_DIR/${IMAGES_SUBDIR%/}" "$WORKDIR"
  else
    cp -vr --reflink=auto "$PROCESS_DIR/$IMAGES_SUBDIR" "$WORKDIR"
  fi
}

pre_clone_to_workdir() {
  # copy the METS and its directory controlled by Kitodo.Presentation
  # to the transient directory controlled by the Manager
  if test -f "$WORKDIR/mets.xml"; then
    # already a workspace - repeated run
    # there is no command for METS synchronization,
    # so just check roughly
    # (also fails if either side is not a valid METS)
    diff -u <(ocrd workspace -m "$METS_PATH" list-page) <(ocrd workspace -d "$WORKDIR" list-page)
  else
    # we cannot use ocrd workspace clone, because it does not offer copying local files
    # (only download all remote or download nothing)
    cp -v "$METS_PATH" "$WORKDIR"/mets.xml
    rsync -T /tmp --exclude=$(basename "$METS_PATH") -av "$(dirname "$METS_PATH")"/ "$WORKDIR"
    # now rename the input file grp to the OCR-D default
    # (cannot use ocrd workspace rename-group due to core#913)
    #ocrd workspace -d "$WORKDIR" rename-group $IMAGES_GRP OCR-D-IMG
    xmlstarlet ed -L -N mods=http://www.loc.gov/mods/v3 -N mets=http://www.loc.gov/METS/ -N xlink=http://www.w3.org/1999/xlink \
               -u "/mets:mets/mets:fileSec/mets:fileGrp[@USE='$IMAGES_GRP']/@USE" -v OCR-D-IMG "$WORKDIR/mets.xml"
    # now remove the output file grp, if it exists
    ocrd workspace -d "$WORKDIR" remove-group -fr $RESULT_GRP
    # workaround for core#485
    ocrd workspace -d "$WORKDIR" remove -f FULLDOWNLOAD
  fi
}

pre_sync_workdir () {
  # copy the data explicitly from Manager to Controller
  rsync -av -e "ssh -p $CONTROLLERPORT -l ocrd" "$WORKDIR/" $CONTROLLERHOST:/data/$REMOTEDIR
}

ocrd_validate_workflow () {
  echo -n 'ocrd validate tasks $OV --workspace . '
  ocrd_format_workflow
}

post_sync_workdir () {
    # copy the results back from Controller to Manager
    rsync -av -e "ssh -p $CONTROLLERPORT -l ocrd" $CONTROLLERHOST:/data/$REMOTEDIR/ "$WORKDIR"
    # TODO: maybe also schedule cleanup (or have a cron job delete dirs in /data which are older than N days)
    # e.g. `ssh --port $CONTROLLERPORT ocrd@$CONTROLLERHOST rm -fr /data/"$WORKDIR"`
}

post_validate_workdir() {
  ocrd workspace -d "$WORKDIR" validate -s mets_unique_identifier -s mets_file_group_names -s pixel_density
}

post_process_to_procdir() {
  imggrp=OCR-D-IMG
  # use last fileGrp as single result
  ocrgrp=$(ocrd workspace -d "$WORKDIR" list-group | tail -1)
  # map and copy to Kitodo filename conventions
  mkdir -p "$PROCESS_DIR/$RESULT_SUBDIR"
  # use the same basename as the input image
  declare -A page2base
  while read page path; do
    page2base["$page"]="$(basename ${path%.*})"
  done < <(ocrd workspace -d "$WORKDIR" find -G $imggrp -k pageId -k local_filename)
  while read page path; do
    basename="${page2base[$page]}"; extension=${path##*.}
    cp -v "$WORKDIR/$path" "$PROCESS_DIR/$RESULT_SUBDIR/$basename.$extension"
  done < <(ocrd workspace -d "$WORKDIR" find -G $ocrgrp -k pageId -k local_filename)
}

post_process_to_mets() {
 # use fileGrp of newest ALTO file as single result
  lastpage=$(ocrd workspace -d "$WORKDIR" \
                  list-page | tail -1)
  ocrgrp=$(ocrd workspace -d "$WORKDIR" \
                find -m "//(application/alto[+]xml|text/xml)" -g ${PAGES:-$lastpage} -k fileGrp | tail -1)
  # fixme: if workflow did not contain ALTO already, convert here via page-to-alto --no-check-border --no-check-words --dummy-word --dummy-textline
  # copy workflow provenance
  mm-update -m "$METS_PATH" add-agent -m "$WORKDIR/mets.xml"
  # extract text result
  mkdir -p "$PROCESS_DIR/$RESULT_GRP"
  while read page path file; do
    # remove any existing files for this page
    #ocrd workspace -m "$METS_PATH" remove -f $(ocrd workspace -m "$METS_PATH" find -G $RESULT_GRP -g $page -k ID)
    mm-update -m "$METS_PATH" remove-files -G $RESULT_GRP -g $page
    # copy and reference new file for this page
    cp -v "$WORKDIR/$path" "$PROCESS_DIR/$RESULT_GRP/"
    fname="$(basename "$path")"
    #ocrd workspace -m "$METS_PATH" add -C -G $RESULT_GRP -i $file -m application/alto+xml -g $page "$RESULT_GRP/$fname"
    # ensure we have LOCTYPE=URL (when adding URL_PREFIX) or LOCTYPE=OTHER (otherwise)
    mm-update -m "$METS_PATH" add-file -G $RESULT_GRP -m application/alto+xml -g $page ${URL_PREFIX:+-u} ${URL_PREFIX} "$PROCESS_DIR/$RESULT_GRP/$fname"
  done < <(ocrd workspace -d "$WORKDIR" \
                find -G $ocrgrp -m "//(application/alto[+]xml|text/xml)" -g "${PAGES:-//.*}" \
                -k pageId -k local_filename -k ID)
  # perhaps if URL_PREFIX:  mm-update -m "$METS_PATH" validate -u $URL_PREFIX
}

close_task() {
  if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT" -a -n "$TASK_ID" -a -n "$PROCESS_ID"; then
    java -Dlog4j2.configurationFile=$ACTIVEMQ_CLIENT_LOG4J2 -jar "$ACTIVEMQ_CLIENT" "tcp://$ACTIVEMQ?closeAsync=false" "KitodoProduction.FinalizeStep.Queue" $TASK_ID $PROCESS_ID
  fi
  logret # communicate retval 0
}

# exit in async or sync mode
close() {
  if test -n "$ACTIVEMQ" -a -n "$ACTIVEMQ_CLIENT" -a -n "$TASK_ID" -a -n "$PROCESS_ID"; then
    logger -p user.info -t $TASK "ocr_exit in async mode - immediate termination of the script"
    # prevent any RETVAL from being written yet
    trap - EXIT
    # fail so Kitodo will listen to the actual time the job is done via ActiveMQ
    exit 1
  else
    # become synchronous again
    logger -p user.info -t $TASK "ocr_exit in sync mode - wait until the processing is completed"
    wait $!
    #rm -f /run/lock/ocrd.jobs/$REMOTEDIR
  fi
}
