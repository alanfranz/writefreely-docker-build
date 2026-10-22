# writefreely container image

Builds [WriteFreely](https://github.com/writefreely/writefreely) from an upstream
release tag on current Go and Alpine, and publishes a multi-arch
(`linux/amd64`, `linux/arm64`) OCI image to GHCR:

    ghcr.io/alanfranz/writefreely:<version>

The release that gets built is set in `WRITEFREELY_VERSION`.

## Image layout

Same as the upstream image, so upstream docs apply:

- working dir `/go`, runs as `daemon`
- config: `/go/config.ini`
- keys: `/go/keys` (volume)
- listens on `8080`
- `writefreely` is on `PATH`

No `HEALTHCHECK` is baked in (OCI images don't carry one); with podman add
`--health-cmd 'wget -q --spider http://localhost:8080/ || exit 1'`, or
`HealthCmd=` in a Quadlet `.container` file.

## Local build

Requires podman (set `PODMAN=docker` to use docker instead).

    make build   # host arch, tagged ghcr.io/alanfranz/writefreely:<version>-<arch>
    make test    # boots it with a throwaway SQLite config and fetches /

## CI

`.github/workflows/build.yml` builds each arch natively on GitHub runners,
smoke-tests it, then assembles the manifest list and pushes it (not on PRs).
