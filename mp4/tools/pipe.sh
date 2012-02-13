#!/bin/bash

src="media/sample.mp4"
dst="sample.ts"
op="-acodec copy -vcodec copy -f mpegts"
filt="-vbsf h264_mp4toannexb"
pass="ffmpeg -i - $op -"
pipe=" | "

cmd="ffmpeg -i $src $filt $op -"
for x in {1..4}; do
  cmd="$cmd $pipe $pass"
done

echo $cmd
set -x
eval $cmd > $dst
set +x

# vim:ts=2:sw=2:sts=2:et:ft=sh

