#!/bin/bash

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

# Omit weak dependencies to avoid pulling kernel-devel and systemtap (~265 MiB) into the image
dnf5 install -y --setopt=install_weak_deps=False \
    quickemu \
    qemu-kvm \
    edk2-ovmf

# Optional explicit dependencies (already pulled via quickemu Requires):
# dnf5 install -y swtpm-tools xorriso zsync

# Defensive cleanup in case build.sh runs outside cache-mounted /var/cache
dnf5 clean all && rm -rf /var/cache/dnf

quickemu --version
qemu-img --version
test -f /usr/share/edk2/ovmf/OVMF_CODE.fd
test -f /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd
