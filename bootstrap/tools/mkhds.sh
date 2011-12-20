#!/bin/bash


cd "$( dirname "$0" )"
f4fpackager="$PWD/../f4fpackager/linux/f4fpackager"
cd "../media/src"

prevf4m=
for br in {1..6}; do
  base="bbc1_hd_p${br}"
  src="$base.mp4"
  f4m="$base.f4m"
  br=$( mediainfo -f "$src" | \
    perl -ne 'print int($1/1000) if /^overall\s+bit\s+rate\s*:\s*(\d+)\s*$/i' )
  $f4fpackager  \
    --input-file=$src \
    --bitrate=$br \
    --external-bootstrap \
    --segment-duration=30 \
    --frames-per-keyframe-interval=$[25*12] \
    --frame-rate=25 \
    $prevf4m
  prevf4m="--manifest-file=$f4m"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

