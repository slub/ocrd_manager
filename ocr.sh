# OCR workflow to be run on ocrd_controller
# (syntax of `ocrd process`)
tesserocr-recognize -P segmentation_level region -P model frak2021 -I OCR-D-IMG -O OCR-D-OCR
# we need ALTO in the end
fileformat-transform -P from-to "page alto" -P script-args "--no-check-border --dummy-word" -I OCR-D-OCR -O FULLTEXT
