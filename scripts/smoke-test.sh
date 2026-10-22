#!/usr/bin/env bash
# Boots the image with a throwaway SQLite config and checks that the
# front page is served and the documented healthcheck passes. Each step is
# its own container sharing a volume, as a real deployment would be.
set -euo pipefail

image=${1:?usage: smoke-test.sh IMAGE}
podman=${PODMAN:-podman}
port=${SMOKE_PORT:-18080}
name=writefreely-smoke-$$

workdir=$(mktemp -d)
cleanup() {
    "$podman" rm -f "$name" >/dev/null 2>&1 || true
    "$podman" volume rm -f "$name" >/dev/null 2>&1 || true
    rm -rf "$workdir"
}
trap cleanup EXIT

cat >"$workdir/config.ini" <<CONF
[server]
bind = 0.0.0.0
port = 8080

[database]
type     = sqlite3
filename = /go/keys/writefreely.db

[app]
site_name         = Smoke Test
host              = http://localhost:${port}
single_user       = false
open_registration = false
CONF
chmod 644 "$workdir/config.ini"

run=("$podman" run -v "$workdir/config.ini:/go/config.ini:ro,Z" -v "$name:/go/keys")

"$podman" run --rm "$image" --version
"${run[@]}" --rm "$image" db init
"${run[@]}" --rm "$image" keys generate
"${run[@]}" -d --name "$name" -p "127.0.0.1:${port}:8080" \
    --health-cmd 'wget -q --spider http://127.0.0.1:8080/' \
    --health-interval disable "$image" >/dev/null

for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${port}/"; then
        "$podman" healthcheck run "$name"
        echo "smoke test OK: $image"
        exit 0
    fi
    sleep 1
done

echo "smoke test FAILED: $image" >&2
"$podman" logs "$name" >&2 || true
exit 1
