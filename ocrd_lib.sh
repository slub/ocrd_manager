#!/bin/bash
# OCR-D utils for ocr processing

set -eu
set -o pipefail

TASK=$(basename $0)

cleanupremote() {
    ssh -Tn -p "${CONTROLLERPORT}" admin@${CONTROLLERHOST} rm -fr /data/$REMOTEDIR
}

logerr() {
  logger -p user.info -t $TASK "terminating with error \$?=$? from ${BASH_COMMAND} on line $(caller)"
  cleanupremote &
  webhook_send_error
}

stopbg() {
  logger -p user.crit -t $TASK "passing SIGKILL to child $!"
  cleanupremote
  # pass signal on to children
  kill -INT $!
}

# initialize variables, create ord-d work directory and exit if something is missing
init() {
  trap logerr ERR
  trap stopbg INT TERM KILL

  PID=$$

  cd /data

  logger -p user.info -t $TASK "ocr_init initialize variables and directory structure"
  logger -p user.notice -t $TASK "running with $* CONTROLLER=${CONTROLLER:-}"

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
      # full path does not start with /workflows/
      # this is not a standard workflow - so make a copy
      # in the workspace and use that path instead
      cp -p "$WORKFLOW" "$WORKDIR/workflow.sh"
      WORKFLOW="$WORKDIR/workflow.sh"
  fi

  if test -z "$CONTROLLER" -o "$CONTROLLER" = "${CONTROLLER#*:}"; then
    logger -p user.error -t $TASK "envvar CONTROLLER='$CONTROLLER' must contain host:port"
    exit 4
  fi
  CONTROLLERHOST=${CONTROLLER%:*}
  CONTROLLERPORT=${CONTROLLER#*:}

  WEBHOOK_RECEIVER_URL=""
  WEBHOOK_KEY_DATA=""

  # create job stats for monitor
  HOME=/tmp mongosh --quiet --norc --eval "use ocrd" --eval "db.OcrdJob.insertOne( {
           pid: $PID,
           time_created: ISODate(\"$(date --rfc-3339=seconds)\"),
           process_id: \"$PROCESS_ID\",
           task_id: \"$TASK_ID\",
           process_dir: \"$PROCESS_DIR\",
           workdir: \"$WORKDIR\",
           remotedir: \"$REMOTEDIR\",
           workflow_file: \"$WORKFLOW\",
           controller_address: \"$CONTROLLER\"
      } )" $DB_CONNECTION | logger -p user.debug -t $TASK

}

logret() {
    HOME=/tmp mongosh --quiet --norc --eval "use ocrd" --eval "db.OcrdJob.findOneAndUpdate( {
             pid: $PID }, { \$set: {
             time_terminated: ISODate(\"$(date --rfc-3339=seconds)\"),
             return_code: $?
        }, \$unset: {
           pid: \"\"
        }})" $DB_CONNECTION | logger -p user.debug -t $TASK
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
  echo "cd '$REMOTEDIR'"
  echo "echo \$\$ > ocrd.pid"
  echo "if test -f mets.xml; then OV=--overwrite; else OV=; ocrd-import -j 1 -i; fi"
}

ocrd_enter_workdir() {
  echo "cd '$REMOTEDIR'"
  echo "echo \$\$ > ocrd.pid"
  echo "if test -f mets.xml; then OV=--overwrite; else OV=; fi"
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
    # (only download all remote or download nothing) core#1149
    cp -v "$METS_PATH" "$WORKDIR"/mets.xml
    rsync -T /tmp --exclude=$(basename "$METS_PATH") -av "$(dirname "$METS_PATH")"/ "$WORKDIR"
    # now rename the input file grp to the OCR-D default
    # (cannot use ocrd workspace rename-group due to core#913)
    #ocrd workspace -d "$WORKDIR" rename-group $IMAGES_GRP OCR-D-IMG
    xmlstarlet ed -L -N mods=http://www.loc.gov/mods/v3 -N mets=http://www.loc.gov/METS/ -N xlink=http://www.w3.org/1999/xlink \
               -u "/mets:mets/mets:fileSec/mets:fileGrp[@USE='$IMAGES_GRP']/@USE" -v OCR-D-IMG "$WORKDIR/mets.xml"
    # broken:
    #mets-alias-filegrp -s input=$IMAGES_GRP -s output=OCR-D-IMG -i "$WORKDIR/mets.xml"
    # now remove the output file grp, if it exists
    ocrd workspace -d "$WORKDIR" remove-group -fr $RESULT_GRP
  fi
}

pre_sync_workdir () {
  # copy the data explicitly from Manager to Controller
  # use admin instead of ocrd to avoid entering worker semaphore via sshrc
  rsync -av -e "ssh -p $CONTROLLERPORT -l admin" "$WORKDIR/" $CONTROLLERHOST:/data/$REMOTEDIR
}

ocrd_validate_workflow () {
  echo -n 'ocrd validate tasks $OV --workspace . '
  ocrd_format_workflow
}

post_sync_workdir () {
    # copy the results back from Controller to Manager
    rsync -av -e "ssh -p $CONTROLLERPORT -l admin" $CONTROLLERHOST:/data/$REMOTEDIR/ "$WORKDIR"
    # schedule cleanup
    cleanupremote
}

post_validate_workdir() {
  ocrd workspace -d "$WORKDIR" validate -s mets_unique_identifier -s mets_file_group_names -s pixel_density -s mets_fileid_page_pcgtsid
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

# exit in async or sync mode
close() {
  if test "$ASYNC" = true; then
    logger -p user.info -t $TASK "ocr_exit in async mode - immediate termination of the script"
    # prevent any RETVAL from being written yet
    trap - EXIT
    exit 1
  else
    # become synchronous again
    logger -p user.info -t $TASK "ocr_exit in sync mode - wait until the processing is completed"
    wait $!
  fi
}

webhook_send() {
  EVENT="${1}"
  MESSAGE="${2}"

  case "$EVENT" in
    INFO|STARTED)
      JOBCOMPLETE=0
      ;;
    ERROR|COMPLETED)
      JOBCOMPLETE=1
      ;;
    *)
      logger -p user.error -t $TASK "Unknown task action type"
      ;;
  esac

  if test -n "$WEBHOOK_RECEIVER_URL" -a -n "$WEBHOOK_KEY_DATA" -a -n "$EVENT"; then
    webhook_request "$WEBHOOK_RECEIVER_URL" "$WEBHOOK_KEY_DATA" "$EVENT" "$MESSAGE"
    if ((JOBCOMPLETE)); then
        logret # communicate retval 0
    fi
  else  
    logger -p user.notice -t $TASK "WEBHOOK_RECEIVER_URL, WEBHOOK_KEY_DATA and suitable webhook event must be set to send a webhook"
  fi
}

webhook_request() {
  echo "{ \"key-data\": \"${2}\", \"event\": \"${3}\", \"message\": \"${4}\" }" | curl -k -X POST -H "Content-Type: application/json" -d @- ${1}
}

webhook_send_info() {
  if test -n "${1}"; then
    webhook_send "INFO" "${1}"
  else
    logger -p user.info -t $TASK "Could not send webhook event info cause no message was specified"
  fi
}

webhook_send_error() {
  MESSAGE="${1:-Error occured during the OCR processing}"
  webhook_send "ERROR" "$MESSAGE"
}

webhook_send_started() {
  MESSAGE="${1:-OCR processing started}"
  webhook_send "STARTED" "$MESSAGE"
}

webhook_send_completed() {
  MESSAGE="${1:-OCR processing completed}"
  webhook_send "COMPLETED" "$MESSAGE"
}
