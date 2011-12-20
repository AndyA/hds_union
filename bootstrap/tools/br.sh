#!/bin/bash

find . -type f | while read f; do
  br=$( mediainfo -f $f | perl -ne 'printf "%010d", $1 if /^overall\s+bit\s+rate\s*:\s*(\d+)\s*$/i' )
  nn="$( dirname $f )/[$br]$( basename $f )"
  echo "$f -> $nn"
  mv $f $nn
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

