# syntax=docker/dockerfile:1.6.0

FROM golang:1.21-alpine3.20 AS linuxkit

ARG LINUXKIT_VERSION=v1.8.2

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



FROM alpine:3.22.2 AS base
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
        device-mapper \
        dmidecode \
        dosfstools \
        e2fsprogs \
        e2fsprogs-extra \
        efibootmgr \
        etcd-ctl \
        eudev \
        findutils \
        gcompat \
        grub-efi \
        haveged \
        hvtools \
        iproute2 \
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
RUN apk add --no-cache findutils patch tar

COPY --from=root /bin /usr/src/image/bin/
COPY --from=root /lib /usr/src/image/lib/
COPY --from=root /sbin /usr/src/image/sbin/
COPY --from=root /etc /usr/src/image/etc/
COPY --from=root /usr /usr/src/image/usr/

COPY patches /tmp/patches

WORKDIR /usr/src/image
# hadolint ignore=DL4006,SC2086
RUN <<-EOF
    echo "Applying patches"
    for p in /tmp/patches/*.patch; do
        echo "Applying ${p}"
        patch -p1 -i "${p}"
    done

    # Fix up more stuff to move everything to /usr
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
# Fix coreutils links
RUN find . -xtype l -ilname ../usr/bin/coreutils -exec ln -sf coreutils {} \;

WORKDIR /usr/src/image
RUN <<-EOF
    # Fix sudo
    chmod +s bin/sudo

    # Add empty dirs to bind mount
    mkdir -p lib/modules
    mkdir -p src

    # setup /etc/ssl
    rm -rf etc/ssl
    mkdir -p etc/ssl/certs/
    cp -rf /etc/ssl/certs/ca-certificates.crt etc/ssl/certs
    ln -s certs/ca-certificates.crt etc/ssl/cert.pem

    # setup /usr/local
    rm -rf local
    ln -s /var/local local

    # setup /usr/libexec/kubernetes
    rm -rf libexec/kubernetes
    ln -s /var/lib/rancher/k3s/agent/libexec/kubernetes libexec/kubernetes

    # cleanup files hostname/hosts
    rm -rf \
        etc/hosts \
        etc/hostname \
        etc/alpine-release \
        etc/apk \
        etc/ca-certificates* \
        etc/os-release
    ln -s /usr/lib/os-release etc/os-release
    rm -rf \
        sbin/apk \
        include \
        lib/apk \
        lib/pkgconfig \
        lib/systemd \
        lib/udev \
        share/apk \
        share/applications \
        share/ca-certificates \
        share/icons \
        share/mkinitfs \
        share/vim/vim*/spell \
        share/vim/vim*/tutor \
        share/vim/vim*/doc
EOF

WORKDIR /output

RUN tar czvf userspace.tar.gz /usr/src/image
