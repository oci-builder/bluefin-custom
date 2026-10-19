# bluefin-custom

Custom [Bluefin](https://projectbluefin.io/) image (`ghcr.io/ublue-os/bluefin:stable`) with:

- **Quickemu**, `qemu-kvm`, `edk2-ovmf` — local VMs with quick, sensible defaults (KVM + UEFI/OVMF firmware)
- **Vivaldi** (stable channel) — Chromium-based browser from the vendor's RPM repo

Built via GitHub Actions, signed with cosign, synced with upstream every Monday at 02:00 UTC. Forked from [`ublue-os/image-template`](https://github.com/ublue-os/image-template).

## Package sources

| Packages | Source | Verification |
| --- | --- | --- |
| quickemu, qemu-kvm, edk2-ovmf | Official Fedora repos (inherited from the base image) | Fedora GPG keys, enforced by dnf |
| vivaldi-stable | `repo.vivaldi.com/archive/rpm/$basearch` (vendor repo) | Vendor GPG key, fingerprint pinned in `build_files/build.sh` — build fails on key rotation |

## Security model

- **Upstream verify**: CI verifies the signature of `ghcr.io/ublue-os/bluefin:stable` against the upstream public key pinned at a commit; the build hard-fails if the upstream key rotates.
- **Image signature**: every published image is cosign-signed. Verify with `cosign.pub` (cosign v3.1.2, old bundle format):

```bash
podman run --rm -v "$PWD/cosign.pub":/cosign.pub:ro,Z ghcr.io/sigstore/cosign/cosign:v3.1.2 \
  verify --new-bundle-format=false --key /cosign.pub ghcr.io/oci-builder/bluefin-custom:latest
```

- **Package audit**: installed packages vs. stock Bluefin, run on the booted system (single line):

```bash
Q='%{NAME}-%{VERSION}.%{ARCH}\n'; podman run --rm --entrypoint rpm ghcr.io/ublue-os/bluefin:stable -qa --qf "$Q" | sort > /tmp/base.txt; rpm -qa --qf "$Q" | sort > /tmp/mine.txt; diff /tmp/base.txt /tmp/mine.txt
```

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
- Justfile recipes: `just build`, `just image_name`, `just generate-build-tags`, `just build-iso`, …
- Vivaldi key rotation: fetch the new key, get its fingerprint via `gpg --show-keys`, update `VIVALDI_GPG_FPR` in `build_files/build.sh`
