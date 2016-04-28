#!/bin/bash

exact-path() {
  (cd `dirname $0`; pwd)
}

DIRNAME=$(exact-path)

DIRS=(
  log
  persistent
  run
  tmp
)

for dir in ${DIRS[*]}; do
  path="$DIRNAME/../$dir"
  if [[ ! -d $path ]]; then
    mkdir $path
  fi
done