#!/usr/bin/env bash
#
# Shared preview-cache key logic. Source this file; do not execute it.
#
# Both preview-thumb.sh and sync-thumbs.sh must use the same key so a scan
# recognises previews generated on demand.

PREVIEW_VERSION=1

preview_key() {
    # <source> <width> <height>
    printf '%s' "v${PREVIEW_VERSION}|$1|cover|$2x$3|preview" \
        | md5sum | cut -d' ' -f1
}
