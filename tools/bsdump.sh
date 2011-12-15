#!/bin/bash

in="bs"
out="bsd"

rm -rf "$out"
mkdir -p "$out"

last=
find "$in" -type f -name \*.bootstrap | sort | while read bs; do
  base="$( basename "$bs" .bootstrap )"
  dump="$out/$base.dump"
  echo "$dump"
  ./f4fpackager/linux/f4fpackager --input-file="$bs" --inspect-bootstrap > "$dump"
  if [ $last ]; then
    diff="$out/$base.diff"
    diff -u "$last" "$dump" > "$diff"
  fi
  last="$dump"
done

# vim:ts=2:sw=2:sts=2:et:ft=sh

