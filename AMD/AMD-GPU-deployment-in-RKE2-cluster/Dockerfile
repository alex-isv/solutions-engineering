FROM registry.suse.com/suse/sle15:latest as builder
ENV ADDITIONAL_MODULES sle-module-desktop-applications, sle-module-development-tools, PackageHub
ARG KERNEL_FULL_VERSION
ARG DRIVERS_VERSION
ARG REPO_URL

RUN  zypper addrepo https://download.opensuse.org/repositories/devel:languages:perl/15.6/devel:languages:perl.repo
RUN  zypper addrepo https://download.opensuse.org/repositories/Education/15.6/Education.repo
RUN  zypper addrepo https://download.opensuse.org/repositories/science/SLE_15_SP5/science.repo
RUN  zypper --gpg-auto-import-keys refresh
RUN  zypper install -y kernel-default-devel
RUN zypper install -y python3-setuptools python3-wheel
RUN zypper --no-gpg-checks install -y https://repo.radeon.com/amdgpu-install/6.3.2/sle/15.6/amdgpu-install-6.3.60302-1.noarch.rpm 
RUN zypper --gpg-auto-import-keys refresh

RUN zypper --gpg-auto-import-keys install -y amdgpu-dkms

RUN depmod ${KERNEL_VERSION}


FROM registry.suse.com/suse/sle15:latest
ARG KERNEL_FULL_VERSION
RUN zypper install -y kmod

RUN mkdir -p /opt/lib/modules/${KERNEL_FULL_VERSION}/updates

COPY --from=builder /lib/modules/${KERNEL_FULL_VERSION}/updates/amd* /opt/lib/modules/${KERNEL_FULL_VERSION}/updates/

COPY --from=builder /lib/modules/${KERNEL_FULL_VERSION}/modules.* /opt/lib/modules/${KERNEL_FULL_VERSION}/

RUN ln -s /lib/modules/${KERNEL_FULL_VERSION}/kernel /opt/lib/modules/${KERNEL_FULL_VERSION}/kernel

# copy firmware
RUN mkdir -p /firmwareDir/updates/amdgpu
COPY --from=builder /lib/firmware/updates/amdgpu /firmwareDir/updates/amdgpu
