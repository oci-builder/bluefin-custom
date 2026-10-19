#!/bin/bash

set -ouex pipefail

cp -avf "/ctx/system_files"/. /

# Bluefin has /opt as a symlink to /var/opt (dangling in the container image),
# keeping /opt writable at runtime. Vivaldi unpacks to /opt/vivaldi, so a real
# directory is needed during the build; the base layout is restored after the
# relocation further below.
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

# The Vivaldi repo is only needed to build the image. Browser updates must
# flow exclusively through image rebuilds (CI), so remove the repo file and
# the package-shipped cron hook from the final image.
rm -f /etc/yum.repos.d/vivaldi*.repo
rm -rf /etc/cron.daily/vivaldi*

# Defensive cleanup in case build.sh runs outside cache-mounted /var/cache
dnf5 clean all && rm -rf /var/cache/dnf

# The vivaldi %post scriptlet spawns `nohup /opt/vivaldi/update-ffmpeg &`
# (proprietary media codecs), which outlives `dnf5 install` and writes to
# /var/opt/vivaldi/media-codecs-*. It is routinely killed mid-download at
# layer commit, leaving partial files in the image. The codecs are optional
# (bundled libffmpeg.so is used by default; on the installed system run
# /opt/vivaldi/update-ffmpeg to install them into writable /var/opt). Wait
# for the download to settle, then restore the base state: the base image
# ships no /var content beyond /var/tmp.
for _ in $(seq 1 60); do
    [ -z "$(find /var/opt -name 'libffmpeg.so.*' 2>/dev/null)" ] && break
    sleep 2
done
rm -rf /var/opt /var/lib/dnf
# dnf left /var/lib itself behind; the base image has no /var/lib at all
rmdir /var/lib 2>/dev/null || true

# Relocate Vivaldi from /opt into immutable /usr (OSTree layout). At boot,
# systemd-tmpfiles recreates /opt/vivaldi as a symlink into /usr via the
# writable /var (see /usr/lib/tmpfiles.d/vivaldi.conf).
install -d /usr/lib/opt
mv /opt/vivaldi /usr/lib/opt/vivaldi

# Restore the base image's /opt -> /var/opt layout
rm -rf /opt
ln -s /var/opt /opt

cat > /usr/lib/tmpfiles.d/vivaldi.conf <<'EOF'
# Vivaldi lives in immutable /usr; /opt/vivaldi is created at boot via the
# writable /var (/opt itself is a symlink to /var/opt).
L+ /var/opt/vivaldi - - - - ../../usr/lib/opt/vivaldi
EOF

# Anchor container signature verification on the installed system, mirroring
# the UBlue convention (see /usr/lib/pki/containers/ublue-os.pub and
# /etc/containers/registries.d/ublue-os.yaml in the base image). This makes
# "bootc upgrade" and podman verify ghcr.io/oci-builder images against our
# key. The old-bundle-format cosign signatures are OCI attachments, hence
# use-sigstore-attachments.
install -D -m644 /ctx/cosign.pub /usr/lib/pki/containers/bluefin-custom.pub

cat > /etc/containers/registries.d/oci-builder.yaml <<'EOF'
docker:
  ghcr.io/oci-builder:
    use-sigstore-attachments: true
EOF

# Add our key to the container policy without touching the existing entries.
jq '.transports.docker["ghcr.io/oci-builder"] = [
    {
        "type": "sigstoreSigned",
        "keyPaths": ["/usr/lib/pki/containers/bluefin-custom.pub"],
        "signedIdentity": {
            "type": "matchRepository"
        }
    }
]' /etc/containers/policy.json > /tmp/policy.json
install -m644 /tmp/policy.json /etc/containers/policy.json
jq -e '.transports.docker["ghcr.io/oci-builder"][0].keyPaths' /etc/containers/policy.json

quickemu --version
qemu-img --version
test -f /usr/share/edk2/ovmf/OVMF_CODE.fd
test -f /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd
rpm -q vivaldi-stable
test -d /usr/lib/opt/vivaldi
test -L /opt
test -f /usr/lib/tmpfiles.d/vivaldi.conf
test ! -e /etc/yum.repos.d/vivaldi.repo
test ! -e /etc/cron.daily/vivaldi
test -f /usr/lib/pki/containers/bluefin-custom.pub
test -f /etc/containers/registries.d/oci-builder.yaml
test ! -e /var/opt
