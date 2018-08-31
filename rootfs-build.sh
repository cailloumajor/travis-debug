#!/usr/bin/env bash
set -Eeuxo pipefail

thisDir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

suite="stretch"
mirror="http://archive.raspbian.org/raspbian"

securityArgs=(
    --cap-add SYS_ADMIN
    --cap-drop SETFCAP
)
if docker info | grep -q apparmor; then
    # AppArmor blocks mount :)
    securityArgs+=(
        --security-opt "apparmor=unconfined"
    )
fi

ver="$("${thisDir}/debuerreotype/scripts/debuerreotype-version")"
ver="${ver%% *}"
raspbianDockerImage="debuerreotype/debuerreotype:${ver}-raspbian"
docker build \
    --build-arg version="$ver" \
    -t "$raspbianDockerImage" \
    - < Dockerfile.debuerreotype

docker run \
    --rm \
    "${securityArgs[@]}" \
    --tmpfs /tmp:dev,exec,suid,noatime \
    -w /tmp \
    -v "$thisDir":/host \
    -e suite="$suite" \
    -e mirror="$mirror" \
    -e TZ='UTC' -e LC_ALL='C' \
    "$raspbianDockerImage" \
    bash -Eeuxo pipefail -c '
        wget -O Release.gpg "$mirror/dists/$suite/Release.gpg"
        wget -O Release "$mirror/dists/$suite/Release"
        gpgv --keyring /usr/share/keyrings/raspbian-archive-keyring.gpg \
            Release.gpg Release

        apt-get update
        apt-get install -y --no-install-recommends \
            binfmt-support qemu-user-static
        debuerreotype-init \
            --non-debian \
            `#--debootstrap qemu-debootstrap` \
            --arch armhf \
            --keyring /usr/share/keyrings/raspbian-archive-keyring.gpg \
            rootfs "$suite" "$mirror"
        debuerreotype-minimizing-config rootfs
        debuerreotype-apt-get rootfs update -qq
        debuerreotype-apt-get rootfs dist-upgrade -yqq
        debuerreotype-apt-get rootfs install -y --no-install-recommends \
            iputils-ping iproute2
        debuerreotype-slimify rootfs
        debuerreotype-tar rootfs rootfs.tar.xz

        cp rootfs.tar.xz /host
    '
