#!/usr/bin/env bash
# Boots the image as a throwaway single-user SQLite instance and checks that
# the documented healthcheck passes both before and after the admin user
# exists (a fresh single-user instance 404s on / until then), and that the
# blog is served afterwards. Each step is its own container sharing a volume.
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
single_user       = true
open_registration = false
CONF
chmod 644 "$workdir/config.ini"

run=("$podman" run -v "$workdir/config.ini:/go/config.ini:ro,Z" -v "$name:/go/keys")

"$podman" run --rm "$image" --version
"${run[@]}" --rm "$image" db init
"${run[@]}" --rm "$image" keys generate
fail() {
    echo "smoke test FAILED: $image: $*" >&2
    "$podman" logs "$name" >&2 || true
    exit 1
}
http_status() {
    curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}$1" || true
}

"${run[@]}" -d --name "$name" -p "127.0.0.1:${port}:8080" \
    --health-cmd 'wget -q --spider http://127.0.0.1:8080/login' \
    --health-interval disable "$image" >/dev/null

for _ in $(seq 1 30); do
    [[ $(http_status /login) == 200 ]] && break
    sleep 1
done
[[ $(http_status /login) == 200 ]] || fail "server did not come up"

"$podman" healthcheck run "$name" >/dev/null || fail "unhealthy before the admin user exists"

"${run[@]}" --rm "$image" user create --admin smoke:smoke-password
[[ $(http_status /) == 200 ]] || fail "blog not served after creating the admin user"
"$podman" healthcheck run "$name" >/dev/null || fail "unhealthy after the admin user exists"

echo "smoke test OK: $image"
