#!/bin/bash
# Builds StatsDirect Viewer.app without a local .NET SDK. The container
# publishes the managed engine and stages the macOS .NET runtime; Swift, the
# C++ dylibs, codesigning and the tests then run here, because no container
# can produce a signed macOS application.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"
DOCKER_BIN="${DOCKER:-$(command -v docker || true)}"
if [[ -z "$DOCKER_BIN" ]]; then
  printf 'Install Docker, or set DOCKER to its executable.\n' >&2
  exit 1
fi
IMAGE="${STATSDIRECT_DOCKER_IMAGE:-statsdirect-engine-build}"
BUILD_WORK="${STATSDIRECT_BUILD_WORK:-$REPO/.build}"
mkdir -p "$BUILD_WORK"
BUILD_WORK="$(cd "$BUILD_WORK" && pwd -P)"

mounts=(--volume "$REPO:/work")
case "$BUILD_WORK" in
  "$REPO"/*) CONTAINER_WORK="/work${BUILD_WORK#"$REPO"}" ;;
  *) mounts+=(--volume "$BUILD_WORK:/build-work"); CONTAINER_WORK="/build-work" ;;
esac

"$DOCKER_BIN" build --tag "$IMAGE" --file Docker/Dockerfile Docker
"$DOCKER_BIN" run --rm --user "$(id -u):$(id -g)" "${mounts[@]}" \
  --env STATSDIRECT_BUILD_WORK="$CONTAINER_WORK" "$IMAGE"

export STATSDIRECT_ENGINE_PREBUILT=1
exec ./build.sh
