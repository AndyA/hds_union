#!/bin/bash

outdir="media/hds"
indir="media/src"

mkdir -p "$outdir"
for br in {1..6}; do
  src="$indir/bbc1_hd_p${br}.mp4"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

