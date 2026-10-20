#!/usr/bin/env sh
set -eu

tool_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$tool_dir/../.." && pwd)
mode=${1:-generate}
case "$mode" in generate|--check) ;; *) echo "Usage: $0 [--check]" >&2; exit 2 ;; esac
protoc_bin=${PROTOC:-protoc}
if [ "$("$protoc_bin" --version)" != "libprotoc 36.2" ]; then
  echo "Required protoc version: 36.2" >&2
  exit 1
fi
temporary=$(mktemp -d "${TMPDIR:-/tmp}/ffido-proto.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
"$protoc_bin" --proto_path="$root/contracts" \
  --dart_out="grpc:$temporary" \
  --plugin="protoc-gen-dart=$tool_dir/protoc-gen-dart" \
  "$root/contracts/ffido/v1/ffido.proto"
destination="$root/apps/frontend/lib/api/generated"
if [ "$mode" = --check ]; then
  diff -ru "$destination" "$temporary"
else
  mkdir -p "$destination"
  # Каталог принадлежит генератору; удаляем только его устаревшие Dart-файлы.
  find "$destination" -type f -name '*.dart' -delete
  find "$destination" -mindepth 1 -depth -type d -empty -delete
  cp -R "$temporary/." "$destination/"
fi
