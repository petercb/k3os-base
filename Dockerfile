# syntax=docker/dockerfile:1.6.0

FROM golang:1.21-alpine3.18 AS linuxkit

ARG LINUXKIT_VERSION=v1.2.0

ENV CGO_ENABLED=0
ENV GO111MODULE off

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

WORKDIR /output

ADD https://github.com/linuxkit/linuxkit.git#${LINUXKIT_VERSION} \
    "${GOPATH}/src/github.com/linuxkit/linuxkit"

WORKDIR ${GOPATH}/src/github.com/linuxkit/linuxkit/pkg/metadata
RUN go build \
        -ldflags "-extldflags -static -s" \
        -o /output/metadata



FROM alpine:3.18.6 AS base
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]


FROM base AS root
ARG TARGETARCH

# hadolint ignore=DL3018
RUN <<-EOF
    apk --no-cache add \
        bash \
        bash-completion \
        blkid \
        busybox-extras-openrc \
        busybox-openrc \
        ca-certificates \
        connman \
        conntrack-tools \
        coreutils \
        cryptsetup \
        curl \
        dbus \
        dmidecode \
        dosfstools \
        e2fsprogs \
        e2fsprogs-extra \
        efibootmgr \
        eudev \
        findutils \
        gcompat \
        grub-efi \
        haveged \
        hvtools \
        iproute2 \
        iptables \
        irqbalance \
        iscsi-scst \
        jq \
        kbd-bkeymaps \
        lm-sensors \
        libc6-compat \
        libusb \
        logrotate \
        lsscsi \
        lvm2 \
        lvm2-extra \
        mdadm \
        mdadm-misc \
        mdadm-udev \
        multipath-tools \
        ncurses \
        ncurses-terminfo \
        nfs-utils \
        open-iscsi \
        openrc \
        openssh-client \
        openssh-server \
        openssl \
        parted \
        procps \
        qemu-guest-agent \
        rng-tools \
        rsync \
        strace \
        strongswan \
        smartmontools \
        sudo \
        tar \
        tzdata \
        util-linux \
        virt-what \
        vim \
        wireguard-tools \
        wpa_supplicant \
        xfsprogs \
        xz
    mv -vf /etc/conf.d/qemu-guest-agent /etc/conf.d/qemu-guest-agent.orig
    mv -vf /etc/conf.d/rngd             /etc/conf.d/rngd.orig
    mv -vf /etc/conf.d/udev-settle      /etc/conf.d/udev-settle.orig
    if [ "$TARGETARCH" = "amd64" ]; then
        apk --no-cache add grub-bios
    fi
EOF

COPY --from=linuxkit /output/metadata /sbin/metadata


FROM base AS output

# hadolint ignore=DL3018
RUN apk add --no-cache findutils tar

COPY --from=root /bin /usr/src/image/bin/
COPY --from=root /lib /usr/src/image/lib/
COPY --from=root /sbin /usr/src/image/sbin/
COPY --from=root /etc /usr/src/image/etc/
COPY --from=root /usr /usr/src/image/usr/

# Fix up more stuff to move everything to /usr
WORKDIR /usr/src/image
# hadolint ignore=DL4006,SC2086
RUN <<-EOF
    for i in usr/*; do
        if [ -e "$(basename $i)" ]; then
            tar cf - "$(basename $i)" | tar xf - -C usr
            rm -rf "$(basename $i)"
        fi
        mv $i .
    done
    rmdir usr
EOF

WORKDIR /usr/src/image/bin
RUN <<-EOF
    # Fix coreutils links
    find . -xtype l -ilname ../usr/bin/coreutils -exec ln -sf coreutils {} \;

    # Fix sudo
    chmod +s /usr/src/image/bin/sudo

    # Add empty dirs to bind mount
    mkdir -p /usr/src/image/lib/modules
    mkdir -p /usr/src/image/src

    # setup /etc/ssl
    rm -rf /usr/src/image/etc/ssl
    mkdir -p /usr/src/image/etc/ssl/certs/
    cp -rf /etc/ssl/certs/ca-certificates.crt /usr/src/image/etc/ssl/certs
    ln -s certs/ca-certificates.crt /usr/src/image/etc/ssl/cert.pem

    # setup /usr/local
    rm -rf /usr/src/image/local
    ln -s /var/local /usr/src/image/local
    # setup /usr/libexec/kubernetes
    rm -rf /usr/src/image/libexec/kubernetes
    ln -s /var/lib/rancher/k3s/agent/libexec/kubernetes \
        /usr/src/image/libexec/kubernetes

    # cleanup files hostname/hosts
    rm -rf \
        /usr/src/image/etc/hosts \
        /usr/src/image/etc/hostname \
        /usr/src/image/etc/alpine-release \
        /usr/src/image/etc/apk \
        /usr/src/image/etc/ca-certificates* \
        /usr/src/image/etc/os-release
    ln -s /usr/lib/os-release /usr/src/image/etc/os-release
    rm -rf \
        /usr/src/image/sbin/apk \
        /usr/src/image/include \
        /usr/src/image/lib/apk \
        /usr/src/image/lib/pkgconfig \
        /usr/src/image/lib/systemd \
        /usr/src/image/lib/udev \
        /usr/src/image/share/apk \
        /usr/src/image/share/applications \
        /usr/src/image/share/ca-certificates \
        /usr/src/image/share/icons \
        /usr/src/image/share/mkinitfs \
        /usr/src/image/share/vim/vim*/spell \
        /usr/src/image/share/vim/vim*/tutor \
        /usr/src/image/share/vim/vim*/doc
EOF

WORKDIR /output

RUN tar czvf userspace.tar.gz /usr/src/image
