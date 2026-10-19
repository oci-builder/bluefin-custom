# bluefin-custom

Custom [Bluefin](https://projectbluefin.io/) image (`ghcr.io/ublue-os/bluefin:stable`) with:

- **Quickemu**, `qemu-kvm`, `edk2-ovmf` — local VMs with quick, sensible defaults (KVM + UEFI/OVMF firmware)
- **Vivaldi** (stable channel) — Chromium-based browser from the vendor's RPM repo

Built via GitHub Actions, signed with cosign, synced with upstream every Monday at 02:00 UTC. Forked from [`ublue-os/image-template`](https://github.com/ublue-os/image-template).

## Package sources

| Packages | Source | Verification |
| --- | --- | --- |
| quickemu, qemu-kvm, edk2-ovmf | Official Fedora repos (inherited from the base image) | Fedora GPG keys, enforced by dnf |
| vivaldi-stable | `repo.vivaldi.com/archive/rpm/$basearch` (vendor repo, build-time only — removed from the final image) | Vendor GPG key, fingerprint pinned in `build_files/build.sh` — build fails on key rotation |

## Security model

- **Upstream verify**: CI verifies the signature of `ghcr.io/ublue-os/bluefin:stable` against the upstream public key pinned at a commit; the build hard-fails if the upstream key rotates.
- **Image signature**: every published image is cosign-signed. Verify with `cosign.pub` (cosign v3.1.2, old bundle format):

```bash
podman run --rm -v "$PWD/cosign.pub":/cosign.pub:ro,Z ghcr.io/sigstore/cosign/cosign:v3.1.2 \
  verify --new-bundle-format=false --key /cosign.pub ghcr.io/oci-builder/bluefin-custom:latest
```

- **In-image signature anchoring**: the image ships the public key (`/usr/lib/pki/containers/bluefin-custom.pub`), a matching `/etc/containers/policy.json` entry, and `/etc/containers/registries.d/oci-builder.yaml` — the same mechanism UBlue uses for `ghcr.io/ublue-os`. On the booted system, `bootc upgrade` and podman only accept this image if it is signed with the key.

- **Package audit**: installed packages vs. stock Bluefin, run on the booted system (single line):

```bash
Q='%{NAME}-%{VERSION}.%{ARCH}\n'; podman run --rm --entrypoint rpm ghcr.io/ublue-os/bluefin:stable -qa --qf "$Q" | sort > /tmp/base.txt; rpm -qa --qf "$Q" | sort > /tmp/mine.txt; diff /tmp/base.txt /tmp/mine.txt
```

## Image layout

- **Vivaldi**: lives in immutable `/usr/lib/opt/vivaldi` (OSTree layout). At boot, `systemd-tmpfiles` recreates `/opt/vivaldi` as a symlink into `/usr` (`/usr/lib/tmpfiles.d/vivaldi.conf`); the base image's `/opt -> /var/opt` layout is kept.
- **No vendor repo in the image**: the Vivaldi repo file and the package's cron hook are removed after install; browser updates happen exclusively via image rebuild (weekly sync).
- **Proprietary media codecs are optional**: the package's install scriptlet runs an asynchronous `update-ffmpeg` download that would leave partial files in the image; `build.sh` waits for it and restores the base state. The bundled `libffmpeg.so` is used by default; to install the proprietary codecs on the installed system, run `sudo /opt/vivaldi/update-ffmpeg` (writes to writable `/var/opt`).

## Tags

Generated via `just generate-build-tags`:

- `latest`
- `latest-YYYYMMDD` & `YYYYMMDD`
- `latest-<sha>`, `latest-YYYYMMDD-<sha>`, `YYYYMMDD-<sha>`

## Switch

```bash
sudo bootc switch ghcr.io/oci-builder/bluefin-custom:latest
sudo reboot
```

Confirm with `bootc status` (booted image should be `ghcr.io/oci-builder/bluefin-custom:latest`) and `quickemu --version`.

First VM: add the user to the `kvm` group, then log out and back in:

```bash
sudo usermod -aG kvm "$USER"
```

## Rollback

```bash
sudo bootc rollback && sudo reboot
# Or pin a specific build:
sudo bootc switch ghcr.io/oci-builder/bluefin-custom:latest-YYYYMMDD
```

## Maintenance

- `build_files/build.sh` — fail-fast package install, includes the Vivaldi GPG key pin
- `.github/workflows/build.yml` — upstream verify, build, rechunk, tag, push, sign; cron `0 2 * * 1`
- `.github/workflows/build-disk.yml` — optional QCOW2/ISO builds via workflow dispatch (artifacts kept 5 days)
- Justfile recipes: `just build`, `just image_name`, `just generate-build-tags`, `just build-iso`, …
- Vivaldi key rotation: fetch the new key, get its fingerprint via `gpg --show-keys`, update `VIVALDI_GPG_FPR` in `build_files/build.sh`
