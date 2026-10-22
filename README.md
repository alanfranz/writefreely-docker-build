# writefreely container image

Builds [WriteFreely](https://github.com/writefreely/writefreely) from an upstream
release tag on current Go and Alpine, and publishes a
`linux/amd64` OCI image to GHCR:

    ghcr.io/alanfranz/writefreely:<version>

The release that gets built is set in `WRITEFREELY_VERSION`.

## Image layout

Same as the upstream image, so upstream docs apply:

- working dir `/go`, runs as uid/gid `2` (`daemon`)
- config: `/go/config.ini`
- keys: `/go/keys` (volume)
- listens on `8080`
- `writefreely` is on `PATH`, e.g. `podman exec <ctr> writefreely user create ...`

The image is `FROM scratch` and is a single layer: a static binary, its
templates/static assets, CA certificates and `/tmp`. There is no shell,
`wget`, package manager or timezone database (WriteFreely doesn't use one),
so a `HEALTHCHECK` cannot be run inside the container.

## Local build

Requires podman (set `PODMAN=docker` to use docker instead).

    make build   # linux/amd64, tagged ghcr.io/alanfranz/writefreely:<version>
    make test    # boots it with a throwaway SQLite config and fetches /

## CI

`.github/workflows/build.yml` builds and smoke-tests the image on every push and
PR, and pushes it to GHCR (not on PRs).
