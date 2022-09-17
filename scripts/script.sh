#!/bin/bash

trap 'rm -f ${EXE_NAME} $' EXIT

# line number where payload starts
PAYLOAD_LINE=$(awk '/^__PAYLOAD_BEGINS__/ { print NR + 1; exit 0; }' $0)

# name of an embedded binary executable
EXE_NAME=/tmp/nx3all

# extract the embedded binary executable
tail -n +${PAYLOAD_LINE} $0 | base64 -d | cat > ${EXE_NAME}
chmod +x ${EXE_NAME}

# run the executable as needed
${EXE_NAME} $@

exit 0
__PAYLOAD_BEGINS__
