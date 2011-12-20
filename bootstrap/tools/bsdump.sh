#!/bin/bash

in="bsfenkle"

last=
find "$in" -type f -name \*.bootstrap | sort | while read bs; do
  base="$( basename "$bs" .bootstrap )"
  dump_bs="$in/$base.bs.pl"
  dump_pl="$in/$base.pl.pl"
  echo "$dump_bs"
  perl tools/boot2pl "$bs" > "$dump_bs"
  perl tools/munge.pl "$bs" > "$dump_pl"
  if [ $last ]; then
    diff="$in/$base.diff"
    diff -u "$last" "$dump_bs" > "$diff" && rm -f "$diff"
  fi
  last="$dump_bs"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

