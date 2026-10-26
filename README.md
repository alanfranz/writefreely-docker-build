# writefreely container image

Builds [WriteFreely](https://github.com/writefreely/writefreely) from an upstream
release tag on current Go and Alpine, and publishes a
`linux/amd64` OCI image to GHCR:

    ghcr.io/alanfranz/writefreely:<version>_<build>

The release that gets built is set in `WRITEFREELY_VERSION`.

## Tags

- `<version>_<build>`, e.g. `0.17.2_12`: `<version>` is the WriteFreely
  release and `<build>` is the CI workflow run number (`github.run_number`).
  The build number goes up with every run and doesn't reset when the
  WriteFreely version changes. It has gaps, because PR runs and failed runs
  use up numbers too. These tags are never overwritten: a rebuild with, say,
  a newer Go or Alpine gets a new build number, and a push to a tag that
  already exists (e.g. re-running a CI run) fails.
- `latest` is the only tag that moves. It points to the most recent build.

The plain `0.17.2` tag is from before this scheme and is no longer updated.

**This image targets single-user deployments** (`single_user = true` in
`config.ini`). That is the only mode the CI smoke test exercises, and the
healthcheck below is chosen for it. Multi-user instances will probably run,
but they are not tested or supported here.

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
declare it when you create the container. The check is:

    wget -q --spider http://127.0.0.1:8080/login

Don't check `/`. On a single-user instance `/` is the blog itself, and it
returns 404 until the admin user has been created (`writefreely user create
--admin ...`). A check on `/` would report a freshly deployed container as
unhealthy, and with `HealthOnFailure=kill` it would be restarted over and over
before you get a chance to create that user. `/login` returns 200 whether or
not the admin exists. The CI smoke test checks both states.

Use the port from `[server] port` in `config.ini` if you changed it.

With `podman run`:

    podman run -d --name writefreely \
      -v ./config.ini:/go/config.ini:ro,Z \
      -v writefreely-keys:/go/keys \
      -p 8080:8080 \
      --health-cmd 'wget -q --spider http://127.0.0.1:8080/login' \
      --health-interval 30s --health-retries 3 --health-start-period 10s \
      ghcr.io/alanfranz/writefreely:0.17.2_<build>

    podman healthcheck run writefreely   # run it once by hand; exit 0 = healthy
    podman ps                            # STATUS shows (healthy) / (unhealthy)

Scheduled checks rely on systemd timers, which podman sets up itself on
systemd hosts; elsewhere only `podman healthcheck run` works.

With a Quadlet unit (`~/.config/containers/systemd/writefreely.container`):

    [Container]
    Image=ghcr.io/alanfranz/writefreely:0.17.2_<build>
    Volume=%h/writefreely/config.ini:/go/config.ini:ro,Z
    Volume=writefreely-keys:/go/keys
    PublishPort=8080:8080
    HealthCmd=wget -q --spider http://127.0.0.1:8080/login
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
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:8080/login"]
      interval: 30s
      retries: 3
      start_period: 10s

## Local build

Requires podman (set `PODMAN=docker` to use docker instead).

    make build   # linux/amd64, tagged ghcr.io/alanfranz/writefreely:<version>_dev
    make test    # boots a throwaway single-user SQLite instance and runs the healthcheck

## CI

`.github/workflows/build.yml` builds and smoke-tests the image on every push and
PR, except for changes that only touch Markdown files. On pushes to `main` (and
manual runs) it then pushes `<version>_<run number>` to GHCR and moves `latest`
to it (`scripts/push.sh`, which needs skopeo). Publishing runs are serialized, so
`latest` always ends up on the highest build number.

`make push` needs a numeric `BUILD_NUMBER`, so local `_dev` builds can't be
pushed by accident.
