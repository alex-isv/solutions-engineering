# Deployment steps for AMD GPU in SUSE/Rancher Kubernetes stack

## Purpose 
These steps outlines installation of AMD GPU Device Plugin in SUSE RKE2 Kubernetes cluster and managed by a Rancher server.

## Prerequisites

Please review [AMD GPU device plugin for Kubernetes](https://github.com/ROCm/k8s-device-plugin#amd-gpu-device-plugin-for-kubernetes).

<ins> Setup environment </ins>

SLES 15 sp5 based RKE2 cluster with a Rancher manager.

MI210 AMD GPU installed in the worker node.

- **Install ROCM on the worker (GPU) node**

Install ROCM on the worker node as per [SUSE Linux Enterprise native installation section](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/tutorial/quick-start.html)

````
sudo zypper addrepo https://download.opensuse.org/repositories/devel:languages:perl/15.5/devel:languages:perl.repo

sudo zypper install kernel-default-devel
sudo usermod -a -G render,video $LOGNAME # Adding current user to Video, Render groups. See prerequisites.
sudo zypper --no-gpg-checks install https://repo.radeon.com/amdgpu-install/6.1.2/sle/15.5/amdgpu-install-6.1.60102-1.noarch.rpm
sudo zypper refresh
sudo zypper install amdgpu-dkms
sudo zypper install rocm
````