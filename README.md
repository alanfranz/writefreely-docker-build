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
templates/static assets, CA certificates, `/tmp`, and a static busybox that
provides only `/bin/sh` and `wget` (~1 MB, there so healthchecks can run).
There is no package manager or timezone database (WriteFreely doesn't use one).

## Healthcheck

No healthcheck is baked into the image (OCI images can't carry one), so
declare it when you create the container. WriteFreely serves its front page
once it's up, so this checks it:

    wget -q --spider http://127.0.0.1:8080/

Use the port from `[server] port` in `config.ini` if you changed it.

With `podman run`:

    podman run -d --name writefreely \
      -v ./config.ini:/go/config.ini:ro,Z \
      -v writefreely-keys:/go/keys \
      -p 8080:8080 \
      --health-cmd 'wget -q --spider http://127.0.0.1:8080/' \
      --health-interval 30s --health-retries 3 --health-start-period 10s \
      ghcr.io/alanfranz/writefreely:0.17.2

    podman healthcheck run writefreely   # run it once by hand; exit 0 = healthy
    podman ps                            # STATUS shows (healthy) / (unhealthy)

Scheduled checks rely on systemd timers, which podman sets up itself on
systemd hosts; elsewhere only `podman healthcheck run` works.

With a Quadlet unit (`~/.config/containers/systemd/writefreely.container`):

    [Container]
    Image=ghcr.io/alanfranz/writefreely:0.17.2
    Volume=%h/writefreely/config.ini:/go/config.ini:ro,Z
    Volume=writefreely-keys:/go/keys
    PublishPort=8080:8080
    HealthCmd=wget -q --spider http://127.0.0.1:8080/
    HealthInterval=30s
    HealthRetries=3
    HealthStartPeriod=10s
    # restart the container when the check keeps failing
    HealthOnFailure=kill
    # systemd considers the unit started only once the check first passes
    Notify=healthy

    [Service]
    Restart=always

    [Install]
    WantedBy=default.target

With docker / compose, the same command goes in `healthcheck.test`:

    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8080/"]
      interval: 30s
      retries: 3
      start_period: 10s

## Local build

Requires podman (set `PODMAN=docker` to use docker instead).

    make build   # linux/amd64, tagged ghcr.io/alanfranz/writefreely:<version>
    make test    # boots it with a throwaway SQLite config and fetches /

## CI

`.github/workflows/build.yml` builds and smoke-tests the image on every push and
PR, and pushes it to GHCR (not on PRs).
