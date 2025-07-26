# AMD GPU container driver for SLES in AMD gpu-operator deployment
FROM registry.suse.com/suse/sle15:15.6 as builder
ENV ADDITIONAL_MODULES sle-module-desktop-applications, sle-module-development-tools, sle-module-basesystem, PackageHub
RUN zypper -n in SUSEConnect
RUN SUSEConnect --regcode "your reg code"
ARG KERNEL_FULL_VERSION
ARG DRIVERS_VERSION
ARG REPO_URL

RUN  zypper addrepo https://download.opensuse.org/repositories/devel:languages:perl/15.6/devel:languages:perl.repo
RUN  zypper addrepo https://download.opensuse.org/repositories/Education/15.6/Education.repo
RUN  zypper addrepo https://download.opensuse.org/repositories/science/SLE_15_SP5/science.repo
RUN  zypper --gpg-auto-import-keys refresh
RUN  zypper install -y kernel-default-devel
RUN zypper install -y python3-setuptools python3-wheel
RUN zypper --no-gpg-checks install -y https://repo.radeon.com/amdgpu-install/6.4/sle/15.6/amdgpu-install-6.4.60400-1.noarch.rpm
RUN zypper --gpg-auto-import-keys refresh
#RUN zypper install -y mokutil
RUN zypper install -y https://download.opensuse.org/distribution/leap/15.6/repo/oss/x86_64/mokutil-0.5.0-150600.8.3.x86_64.rpm

RUN zypper --gpg-auto-import-keys install -y amdgpu-dkms
# RUN amdgpu-install --usecase=dkms -y
RUN depmod ${KERNEL_VERSION}



FROM registry.suse.com/suse/sle15:15.6
ARG KERNEL_FULL_VERSION
RUN zypper install -y kmod

RUN mkdir -p /opt/lib/modules/${KERNEL_FULL_VERSION}/updates

COPY --from=builder /lib/modules/${KERNEL_FULL_VERSION}/updates/amd* /opt/lib/modules/${KERNEL_FULL_VERSION}/updates/

COPY --from=builder /lib/modules/${KERNEL_FULL_VERSION}/modules.* /opt/lib/modules/${KERNEL_FULL_VERSION}/

RUN ln -s /lib/modules/${KERNEL_FULL_VERSION}/kernel /opt/lib/modules/${KERNEL_FULL_VERSION}/kernel

# copy firmware
RUN mkdir -p /firmwareDir/updates/amdgpu
COPY --from=builder /lib/firmware/updates/amdgpu /firmwareDir/updates/amdgpu
