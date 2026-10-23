#!/bin/sh
# Usage: checksum.sh sha256|md5 FILE...
# Settings arrive as environment variables: FINDERPLUS_SETTING_NAMEONLY = true|false.
set -eu
algorithm="$1"
shift
for file in "$@"; do
    if [ "$algorithm" = "md5" ]; then
        sum=$(/sbin/md5 -q "$file")
    else
        sum=$(/usr/bin/shasum -a 256 "$file" | cut -d ' ' -f 1)
    fi
    if [ "${FINDERPLUS_SETTING_NAMEONLY:-true}" = "true" ]; then
        printf '%s  %s\n' "$sum" "$(basename "$file")"
    else
        printf '%s  %s\n' "$sum" "$file"
    fi
done
