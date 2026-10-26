#!/usr/bin/env bash
# Pushes LOCAL_IMAGE as IMAGE:TAG and then moves IMAGE:latest to it.
# Versioned tags are immutable: if IMAGE:TAG already exists in the registry
# (e.g. a re-run of a CI run, which keeps its run number), nothing is pushed
# and the script fails. Needs skopeo to look up the remote tag.
set -euo pipefail

local_image=${1:?usage: push.sh LOCAL_IMAGE IMAGE TAG}
image=${2:?usage: push.sh LOCAL_IMAGE IMAGE TAG}
tag=${3:?usage: push.sh LOCAL_IMAGE IMAGE TAG}
podman=${PODMAN:-podman}

if out=$(skopeo inspect --raw "docker://$image:$tag" 2>&1); then
    echo "refusing to push: $image:$tag already exists" >&2
    exit 1
elif ! grep -qiE 'manifest unknown|name unknown' <<<"$out"; then
    # Anything other than "no such tag" (auth, network...) is not proof
    # that the tag is free.
    echo "could not check whether $image:$tag exists:" >&2
    echo "$out" >&2
    exit 1
fi

"$podman" push "$local_image" "docker://$image:$tag"
"$podman" push "$local_image" "docker://$image:latest"
echo "pushed $image:$tag and moved $image:latest to it"
