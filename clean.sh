#!/bin/sh
# OCR workflow to be run on ocrd_controller
set -x
ocrd workspace remove-group -fr $(ocrd workspace list-group)
rm mets.xml
