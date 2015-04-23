#!/bin/bash
set -e
[ -z "$BENDER_ROOT" -a -d bender -a -f bender.sh ] && BENDER_ROOT=bender
BENDER_ROOT=${BENDER_ROOT:-/opt/bender}
export BUNDLE_GEMFILE="$BENDER_ROOT/vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG
exec "$BENDER_ROOT/ruby/bin/ruby" -rbundler/setup "$BENDER_ROOT/bin/bender" $@