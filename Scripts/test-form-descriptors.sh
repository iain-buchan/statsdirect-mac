#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${DOTNET:-$(command -v dotnet || true)}"
if [[ -z "$sdk" && -x ../../work/dotnet/dotnet ]]; then sdk=../../work/dotnet/dotnet; fi
if [[ -z "$sdk" ]]; then printf 'The descriptor audit requires the .NET SDK. Set DOTNET.\n' >&2; exit 1; fi
export DOTNET_CLI_HOME="$PWD/.build/dotnet-home"
export NUGET_PACKAGES="${NUGET_PACKAGES:-$PWD/.build/nuget}"
mkdir -p .build
"$sdk" run --project Tests/FormDescriptors -c Release -- "$PWD/.build/form-descriptors.json"
