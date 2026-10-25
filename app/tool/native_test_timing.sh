#!/bin/bash
# Optional wall/CPU measurements; preserve the command's exit status and arguments.
linefold_timed() {
  local phase="$1"
  shift
  if [[ "${LINEFOLD_TEST_TIMINGS:-0}" == 1 ]]; then
    local caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local TIMEFORMAT="TIMING ${caller##*/} $phase real=%3R user=%3U sys=%3S"
    time "$@"
  else
    "$@"
  fi
}
