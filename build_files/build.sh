#!/bin/bash

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

# Bluefin has /opt as a symlink to /var/opt (dangling in the container image).
# Vivaldi unpacks to /opt/vivaldi, so replace it with a real directory, as
# recommended by the image-template. akmods is unaffected (installs to
# /lib/modules/<kver>/extra/).
if [ -L /opt ] || [ ! -d /opt ]; then
    rm -f /opt
    mkdir -p /opt
fi

# Vivaldi: vendor repo with pinned GPG key.
# The fingerprint check fails the build if the vendor key rotates, so a
# silent key swap at repo.vivaldi.com never reaches the image.
VIVALDI_GPG_URL="https://repo.vivaldi.com/archive/linux_signing_key.pub"
VIVALDI_GPG_FPR="8D1FA52AEF58A09D889DD4221256C34716BD9233" # Vivaldi Package Composer KEY11, expires 2027-02-07

curl -fsSL "$VIVALDI_GPG_URL" -o /tmp/vivaldi.asc
# Explicit homedir: /root is not writable by gpg in this image, /tmp is tmpfs here
mkdir -p /tmp/gnupg
test "$(gpg --homedir /tmp/gnupg --show-keys --with-colons /tmp/vivaldi.asc | awk -F: '/^fpr/{print $10; exit}')" = "$VIVALDI_GPG_FPR"
mkdir -p /etc/pki/rpm-gpg
install -m644 /tmp/vivaldi.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi

cat > /etc/yum.repos.d/vivaldi.repo <<'EOF'
[vivaldi]
name=Vivaldi stable
baseurl=https://repo.vivaldi.com/archive/rpm/$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi
EOF

# Omit weak dependencies to avoid pulling kernel-devel and systemtap (~265 MiB) into the image
dnf5 install -y --setopt=install_weak_deps=False \
    quickemu \
    qemu-kvm \
    edk2-ovmf \
    vivaldi-stable

# Defensive cleanup in case build.sh runs outside cache-mounted /var/cache
dnf5 clean all && rm -rf /var/cache/dnf

quickemu --version
qemu-img --version
test -f /usr/share/edk2/ovmf/OVMF_CODE.fd
test -f /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd
rpm -q vivaldi-stable
