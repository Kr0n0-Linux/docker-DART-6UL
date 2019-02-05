FROM ubuntu:19.04

LABEL net.caseonit.vm6.version="0.0.1-beta"
LABEL net.caseonit.vm6.release-date="190204"
MAINTAINER carlos@caseonit.net

# Repositories
ARG LINUX_REPO="https://github.com/Kr0n0-Linux/linux-imx_varigit_DART-6UL.git"
ARG UBOOT_REPO="https://github.com/Kr0n0-Linux/uboot-imx_varigit_DART-6UL.git"
ARG BCM_REPO="https://github.com/Kr0n0-Linux/BCM4343_fw_varigit_DART-6UL.git"
ARG TOOLCHAIN_BINARY="gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf.tar.xz"
ARG TOOLCHAIN_REPO="https://releases.linaro.org/components/toolchain/binaries/6.3-2017.05/arm-linux-gnueabihf/${TOOLCHAIN_BINARY}"
ARG MEDUX_BRANCH="medux_01"
ARG ARCH=arm
ARG CROSS_COMPILE=arm-linux-gnueabihf-
ARG TARGET_DIR=/opt/target
ARG BUILD_DIR=/opt/build
ARG KERNEL_DTB='imx6ul-var-dart-emmc_wifi.dtb imx6ul-var-dart-nand_wifi.dtb imx6ul-var-dart-sd_emmc.dtb imx6ul-var-dart-sd_nand.dtb imx6ull-var-dart-emmc_wifi.dtb imx6ull-var-dart-sd_emmc.dtb imx6ull-var-dart-nand_wifi.dtb imx6ull-var-dart-sd_nand.dtb imx6ul-var-dart-5g-emmc_wifi.dtb imx6ull-var-dart-5g-emmc_wifi.dtb imx6ul-var-dart-5g-nand_wifi.dtb imx6ull-var-dart-5g-nand_wifi.dtb'
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /opt

# Dependencies for building
RUN apt-get update
RUN apt-get -y install binfmt-support qemu qemu-user-static debootstrap kpartx \
            lvm2 dosfstools gpart binutils git lib32ncurses5-dev python-m2crypto \
            gawk wget git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat libsdl1.2-dev \
            autoconf libtool libglib2.0-dev libarchive-dev \
            python-git xterm sed cvs subversion coreutils texi2html \
            docbook-utils python-pysqlite2 help2man make gcc g++ desktop-file-utils libgl1-mesa-dev \
            libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils \
            bc debian-archive-keyring

RUN mkdir /opt/toolchain
RUN mkdir -p ${TARGET_DIR}/uboot && mkdir -p ${BUILD_DIR}/uboot
RUN mkdir -p ${TARGET_DIR}/linux && mkdir -p ${BUILD_DIR}/linux
RUN mkdir -p ${TARGET_DIR}/filesystem 

# Checking out repos
RUN cd /opt/toolchain && wget -c ${TOOLCHAIN_REPO}
RUN git clone -v ${UBOOT_REPO} -b ${MEDUX_BRANCH} /opt/uboot.git
RUN git clone -v ${LINUX_REPO} -b ${MEDUX_BRANCH} /opt/linux.git
RUN git clone -v ${BCM_REPO} -b ${MEDUX_BRANCH} /opt/bcm44.git

# ARMHF TOOLCHAIN 
RUN cd /opt/toolchain && tar xfp ${TOOLCHAIN_BINARY} && rm ${TOOLCHAIN_BINARY}
ENV PATH="${PATH}:/opt/toolchain/gcc-linaro-6.3.1-2017.05-x86_64_arm-linux-gnueabihf/bin"

# U-BOOT
COPY configs/medux_uboot_config ${BUILD_DIR}/uboot/.config
RUN cd /opt/uboot.git && KBUILD_OUTPUT=${BUILD_DIR}/uboot make prepare
RUN cd /opt/uboot.git && \ 
    KBUILD_OUTPUT=${BUILD_DIR}/uboot make
RUN cp ${BUILD_DIR}/uboot/SPL ${TARGET_DIR}/uboot/SPL.mmc && \
    cp ${BUILD_DIR}/uboot/u-boot.img ${TARGET_DIR}/uboot/u-boot.img.mmc 

# LINUX KERNEL
COPY configs/medux_kernel_config ${BUILD_DIR}/linux/.config
RUN cd /opt/linux.git && KBUILD_OUTPUT=${BUILD_DIR}/linux make prepare
RUN cd /opt/linux.git && \
    KBUILD_OUTPUT=${BUILD_DIR}/linux make zImage && \
    KBUILD_OUTPUT=${BUILD_DIR}/linux make ${KERNEL_DTB} && \
    KBUILD_OUTPUT=${BUILD_DIR}/linux make modules && \
    KBUILD_OUTPUT=${BUILD_DIR}/linux INSTALL_MOD_PATH=${TARGET_DIR}/linux make modules_install
RUN cp ${BUILD_DIR}/linux/arch/arm/boot/zImage ${TARGET_DIR}/linux/ && \
    cp ${BUILD_DIR}/linux/arch/arm/boot/dts/*.dtb ${TARGET_DIR}/linux/

# BROADCOM FIRMWARE
RUN cd /opt/bcm44.git && \
    install -d ${TARGET_DIR}/linux/lib/firmware/bcm && \
    install -d ${TARGET_DIR}/linux/lib/firmware/brcm && \
    install -m 0644 /opt/bcm44.git/brcm/* ${TARGET_DIR}/linux/lib/firmware/brcm/ && \
    install -m 0644 /opt/bcm44.git/*.hcd ${TARGET_DIR}/linux/lib/firmware/bcm/ && \
    install -m 0644 /opt/bcm44.git/LICENSE ${TARGET_DIR}/linux/lib/firmware/bcm/ && \
    install -m 0644 /opt/bcm44.git/LICENSE ${TARGET_DIR}/linux/lib/firmware/brcm/

# DEBOOTSTRAP FILESYSTEM
RUN cd ${TARGET_DIR}/filesystem && \
    debootstrap --arch=armhf --variant=minbase --include=sysvinit-core --exclude=systemd,systemd-sysv --foreign jessie \
    ${TARGET_DIR}/filesystem http://snapshot.debian.org/archive/debian/20190203/
RUN cp /usr/bin/qemu-arm-static ${TARGET_DIR}/filesystem/usr/bin
RUN cd ${TARGET_DIR}/filesystem && \
    chroot . /debootstrap/debootstrap --second-stage

# Volume expansion
VOLUME /opt/target
