# This Docker file is just a DEMO example to test Intel OpenVino on SLE based container.

FROM registry.suse.com/suse/sle15:15.5

LABEL description="This is the dev image for Intel(R) Distribution of OpenVINO(TM) toolkit on SLES 15 sp5"
LABEL vendor="Intel Corporation"

# ENV no_proxy "localhost,127.0.0.1"
WORKDIR /root/openvino

RUN zypper -n in SUSEConnect

# Add a registration code or use RMT server

# RUN SUSEConnect --regcode INTERNAL-USE-ONLY-****
ADD http://192.168.150.160/repo/rmt-server.crt /etc/pki/trust/anchors/rmt.crt

# Note: <ADD http://...>  is the IP of the local RMT server.
# You need to post rmt-server.crt file on your RMT server in the location which can be reachable from url
# So, on our local RMT server copy /etc/rmt/ssl/rmt-server.crt file to the /usr/share/rmt/public/repo directory, which creates symb link to ./var/lib/rmt/public/repo which is a public repo of RMT server.
# Setup a proper permission to /usr/share/rmt/public/repo directory
# Sync rmt server.
RUN update-ca-certificates
RUN zypper --gpg-auto-import-keys ref -s
RUN zypper --non-interactive up
RUN zypper --no-gpg-checks -n refresh
RUN zypper addrepo https://download.opensuse.org/repositories/home:cabelo:intel/15.5/home:cabelo:intel.repo
RUN zypper --no-gpg-checks -n refresh
RUN SUSEConnect -p PackageHub/15.5/x86_64
RUN zypper --no-gpg-checks -n refresh
RUN SUSEConnect -p sle-module-basesystem/15.5/x86_64
RUN SUSEConnect -p sle-module-server-applications/15.5/x86_64
RUN zypper --no-gpg-checks -n refresh
RUN SUSEConnect -p sle-module-desktop-applications/15.5/x86_64
RUN SUSEConnect -p sle-we/15.5/x86_64
#RUN zypper --no-gpg-checks -n refresh
#RUN SUSEConnect -p sle-module-server-applications/15.5/x86_64
#RUN SUSEConnect -p sle-module-desktop-applications/15.5/x86_64
RUN zypper --no-gpg-checks -n refresh
RUN zypper --non-interactive in cmake pkg-config ade-devel \
                                        patterns-devel-C-C++-devel_C_C++ \
                                        opencl-headers ocl-icd-devel opencv-devel \
                                        pugixml-devel patchelf opencl-cpp-headers \
                                        python311-devel ccache nlohmann_json-devel \
                                        ninja scons git  git-lfs patchelf fdupes \
                                        rpm-build ShellCheck tbb-devel libva-devel \
                                        snappy-devel ocl-icd-devel \
                                        opencl-cpp-headers opencl-headers \
                                        zlib-devel gflags-devel-static \
                                        protobuf-devel curl wget git git-core vim

RUN zypper --no-gpg-checks -n refresh
RUN zypper -n in openvino
RUN zypper -n in libopenvino
RUN zypper -n in openvino-sample
# Review a Build the Sample Applications > https://docs.openvino.ai/2024/learn-openvino/openvino-samples/get-started-demos.html and https://docs.openvino.ai/2024/learn-openvino/openvino-samples/get-started-demos.html#download-model
RUN zypper --no-gpg-checks -n refresh

#Add open_model_zoo for sample demos > https://docs.openvino.ai/2024/omz_demos.html and https://github.com/openvinotoolkit/openvino/tree/master/samples
RUN git clone --recurse-submodules https://github.com/openvinotoolkit/open_model_zoo.git

# As an alternative, if you compiled manually on the local machine -> https://github.com/openvinotoolkit/openvino/blob/master/docs/dev/build_linux.md  (may take some time),
# or > https://en.opensuse.org/SDB:Install_OpenVINO 
# just copy pre-compiled directory to the container.
#COPY "your precompiled directory" ./openvino
