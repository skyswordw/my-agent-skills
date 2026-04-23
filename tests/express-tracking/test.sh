#!/bin/sh

set -eu

ROOT_DIR=$(
  CDPATH= cd -- "$(dirname "$0")/../.." && pwd
)

node --test \
  "$ROOT_DIR/tests/express-tracking/config.test.mjs" \
  "$ROOT_DIR/tests/express-tracking/run.test.mjs"
