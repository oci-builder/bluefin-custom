# bluefin-quickemu

Custom [Bluefin](https://projectbluefin.io/) image (`ghcr.io/ublue-os/bluefin:stable`) with integrated [Quickemu](https://github.com/quickemu-project/quickemu), `qemu-kvm`, and `edk2-ovmf`.

Built via GitHub Actions, signed with `cosign`, and synced weekly with upstream on Mondays at 02:00 UTC. Forked from [`ublue-os/image-template`](https://github.com/ublue-os/image-template).

## Tags

Generated via `just generate-build-tags`:

- `latest`
- `latest-YYYYMMDD` & `YYYYMMDD`
- `latest-<sha>`, `latest-YYYYMMDD-<sha>`, `YYYYMMDD-<sha>`

## Switch & Verify

```bash
podman run --rm -v "$PWD/cosign.pub":/cosign.pub:ro,Z ghcr.io/sigstore/cosign/cosign:v3.1.2 \
  verify --new-bundle-format=false --key /cosign.pub ghcr.io/oci-builder/bluefin-quickemu:latest

sudo bootc switch ghcr.io/oci-builder/bluefin-quickemu:latest
sudo reboot
```

## Rollback

```bash
sudo bootc rollback && sudo reboot
# Or pin a specific build date:
sudo bootc switch ghcr.io/oci-builder/bluefin-quickemu:latest-YYYYMMDD
```
