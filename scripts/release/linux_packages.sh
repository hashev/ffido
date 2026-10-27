#!/usr/bin/env bash
# Install CI packages consistently; Azure's mirror can throttle LLVM downloads.
set -euo pipefail
use_ubuntu_archive() {
  local source
  for source in "$@"; do
    if [[ -f "$source" ]]; then
      sudo sed -E -i 's@https?://azure\.archive\.ubuntu\.com/ubuntu@https://archive.ubuntu.com/ubuntu@g' "$source"
    fi
  done
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "$#" -gt 0 ]] || { echo 'Expected at least one package' >&2; exit 2; }
  use_ubuntu_archive /etc/apt/sources.list.d/ubuntu.sources /etc/apt/apt-mirrors*.txt
  apt_options=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
  sudo apt-get "${apt_options[@]}" update
  sudo apt-get "${apt_options[@]}" install -y "$@"
fi
