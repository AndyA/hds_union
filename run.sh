#!/bin/bash

cd "$(dirname $0)"
export HDS_LT_PATH="$(pwd)/src"
python "$HDS_LT_PATH/com/adobe/fms/tests/threaded_hds_live.py"

# vim:ts=2:sw=2:sts=2:et:ft=sh

