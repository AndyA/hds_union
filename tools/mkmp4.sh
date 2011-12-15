#!/bin/bash

indir="media/00002"
outdir="media/src"

mkdir -p "$outdir"
for br in {1..6}; do
  {
    for frag in {1..100}; do
      ts="$indir/bbc1_hd_p${br}_$( printf '%05d' $frag ).ts"
      cat $ts
    done
  } | ffmpeg -y -i - \
    -acodec copy -vcodec copy -absf aac_adtstoasc \
    "$outdir/bbc1_hd_p${br}.mp4"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

