# Deploying Nvidia GPU-Operator in SUSE based RKE2 cluster

## Purpose
These steps outlines installation of Nvidia gpu-operator in SUSE Kubernetes cluster with SLES based worker nodes and a Rancher server for easy deployment and management.

<ins> Setup environment </ins>

In this test SUSE HARVESTER cluster 1.2.1 with SLE15.5 VMs was used as a base RKE2 cluster and physical SLES based worker nodes with Nvidia GPU installed.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9dfe7c00-8055-4290-8365-d38fbe8cb03f)


You can also integrate a Rancher server with a Harvester cluster for easy cluster management (https://docs.harvesterhci.io/v1.2/rancher/index)


> [!NOTE]
> Verify a support matrix before the installation  (https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-8-2/)

**Installing a Rancher server on SLES**
	Install helm 
# zypper in helm

	Install k3s
Verify the last certified version >> https://github.com/k3s-io/k3s/releases

# curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.10+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -

# k3s kubectl get nodes
NAME          STATUS   ROLES                       AGE   VERSION
cl2-rancher   Ready    control-plane,etcd,master   86s   v1.27.10+k3s1
======
	Install Rancher with helm

 # helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
# kubectl create namespace cattle-system

# kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml
# helm repo add jetstack https://charts.jetstack.io
# helm repo update
# export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace 

#  kubectl get pods --namespace cert-manager
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5dcc4c9b74-8rqtt              1/1     Running   0          34s
cert-manager-cainjector-644bff8d57-tn7t6   1/1     Running   0          34s
cert-manager-webhook-7f6b4fbd47-kv6pn      1/1     Running   0          34s
Verify a certified Rancher version > https://github.com/rancher/rancher/tags

# helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
 # helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=cl2-rancher.isv.suse --set version=2.8.2 --set replicas=1

Login to Rancher URL in the browser and change password.

	Create RKE2 cluster





From Rancher server go to the Cluster Management and select RKE2 and click Custom

Click <Create> and select a proper roles and additional settings

Copy registration command and paste into the terminal of the node which are you are planning to add to the cluster.

Make sure that you have the odd number of nodes in the cluster.
Add a worker node with a GPU installed.


 cl2-vm1:/var/lib/rancher/rke2/bin # ./kubectl get nodes
NAME      STATUS   ROLES                       AGE     VERSION
cl2-vm1   Ready    control-plane,etcd,master   6m56s   v1.27.10+rke2r1
cl2-vm2   Ready    control-plane,etcd,master   11m     v1.27.10+rke2r1
cl2-vm4   Ready    control-plane,etcd,master   6m23s   v1.27.10+rke2r1
r750-a    Ready    worker                      6m6s    v1.27.10+rke2r1



	Install GPU drivers on the worker node
Review compatibility > https://docs.nvidia.com/datacenter/tesla/drivers/index.html#cuda-drivers
and
Platform support > https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html

https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/index.html#suse15


Install CUDA and drivers > https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=SLES&target_version=15&target_type=rpm_network

# sudo zypper addrepo https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/cuda-sles15.repo
# sudo zypper refresh
# sudo zypper install -y cuda-toolkit
# sudo zypper install -y nvidia-open-gfxG05-kmp-default
# sudo zypper install -y cuda-drivers
* Starting with CUDA toolkit 12.2.2, GDS kernel driver package nvidia-gds version 12.2.2-1 (provided by nvidia-fs-dkms 2.17.5-1) and above is only supported with the NVIDIA open kernel driver. Follow the instructions in Removing CUDA Toolkit and Driver to remove existing NVIDIA driver packages and then follow instructions in NVIDIA Open GPU Kernel Modules to install NVIDIA open kernel driver packages.

Review > https://github.com/alexarnoldy/technical-reference-documentation/blob/nvidia-operator-on-BCI/kubernetes/start/nvidia/adoc/gs_rke2-slebci_nvidia-gpu-operator.adoc
# helm repo add nvidia https://helm.ngc.nvidia.com/nvidia

Install the NVIDIA Container Toolkit
# sudo zypper ar https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
# sudo zypper --gpg-auto-import-keys install -y nvidia-container-toolkit
# zypper in nvidia-container-runtime (not needed)



Install gpu-operator with helm command:
helm install -n gpu-operator   --generate-name   --wait   --create-namespace   --version=${OPERATOR_VERSION} 	nvidia/gpu-operator   --set driver.enabled=false   --set operator.defaultRuntime=containerd   --set toolkit.env[0].name=CONTAINERD_CONFIG   --set toolkit.env[0].value=/var/lib/rancher/rke2/agent/etc/containerd/config.toml   --set toolkit.env[1].name=CONTAINERD_SOCKET   --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock   --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS   --set toolkit.env[2].value=nvidia   --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT   --set-string toolkit.env[3].value=true   --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION   --set-string validator.driver.env[0].value=true
–

helm install -n gpu-operator \
  --generate-name \
  --wait \
  --create-namespace \
    nvidia/gpu-operator \
  --set driver.enabled=false \
  --set operator.defaultRuntime=containerd \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/var/lib/rancher/rke2/agent/etc/containerd/config.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia \
  --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT \
  --set-string toolkit.env[3].value=true \
  --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
  --set-string validator.driver.env[0].value=true
=================
~~~~~~~~~`
Error:
RunContainerError (failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: load library failed: libnvidia-ml.so.1: cannot open shared object file: no such file or directory: unknown) | Last state: Terminated with 128: StartError (failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: load library failed: libnvidia-ml.so.1: cannot open shared object file: no such file or directory: unknown), started: Wed, Dec 31 1969 5:00:00 pm, finished: Tue, Feb 20 2024 6:41:52 pm 



~~~~~~~~~~~~
RunContainerError (failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: nvml error: insufficient permissions: unknown) | Last state: Terminated with 128: StartError (failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: nvml error: insufficient permissions: unknown), started: Wed, Dec 31 1969 5:00:00 pm, finished: Tue, Feb 20 2024 6:56:54 pm
~~~~~~~~~
Error: failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: nvml error: insufficient permissions: unknown 
~~~~~~~~~~
CrashLoopBackOff (back-off 5m0s restarting failed container=toolkit-validation pod=nvidia-operator-validator-4g8v4_gpu-operator(39a20cb8-7abb-41f6-aa30-df5fd928a1ea)) | Last state: Terminated with 128: StartError (failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: error during container init: error running hook #0: error running hook: exit status 1, stdout: , stderr: nvidia-container-cli.real: initialization error: nvml error: insufficient permissions: unknown), started: Wed, Dec 31 1969 5:00:00 pm, finished: Thu, Feb 22 2024 10:44:28 am 
~~~~~~~~~~~



===========
To remove CUDA Toolkit:
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"

To remove NVIDIA Drivers:
sudo zypper remove "*nvidia*"
========
Test

helm install -n gpu-operator \
  --generate-name \
  --wait \
  --create-namespace \
    nvidia/gpu-operator \
  --set driver.enabled=false \
  --set operator.defaultRuntime=containerd \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/var/lib/rancher/rke2/agent/etc/containerd/config.toml \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS \
  --set toolkit.env[2].value=nvidia \
  --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT \
  --set-string toolkit.env[3].value=true \
  --set toolkit.version=v1.14.5-centos7 \
  --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
  --set-string validator.driver.env[0].value=true

https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/troubleshooting.html
~~~~~~~~~~~

~~~~~~~~~~~~~~~`latest working version ~~~~~~~~~~`

cl1-b:~ # helm install -n gpu-operator   --generate-name   --wait   --create-namespace 	nvidia/gpu-operator   --set driver.enabled=false   --set operator.defaultRuntime=containerd   --set toolkit.env[0].name=CONTAINERD_CONFIG   --set toolkit.env[0].value=/var/lib/rancher/rke2/agent/etc/containerd/config.toml   --set toolkit.env[1].name=CONTAINERD_SOCKET   --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock   --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS   --set toolkit.env[2].value=nvidia   --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT   --set-string toolkit.env[3].value=true 	--set toolkit.version=v1.14.5-centos7   --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION   --set-string validator.driver.env[0].value=true

~~~~~~~~~~~~~~~~`````
Adding a 2nd worker node to cl1
ErrImagePull (rpc error: code = Unknown desc = failed to pull and unpack image "registry.k8s.io/nfd/node-feature-discovery:v0.14.2": failed to resolve reference "registry.k8s.io/nfd/node-feature-discovery:v0.14.2": failed to do request: Head "https://us-west2-docker.pkg.dev/v2/k8s-artifacts-prod/images/nfd/node-feature-discovery/manifests/v0.14.2": tls: failed to verify certificate: x509: certificate has expired or is not yet valid: current time 2024-01-08T12:57:12-07:00 is before 2024-02-05T08:18:28Z) 
….related to incorrect date set on the linux (was set to the HW which had wrong date)



2 worker nodes with 1 x A100 80Gb and 2 x A100 40Gb
….
So, use steps from > https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/index.html#suse15
=============
This section includes instructions for installing the NVIDIA driver on SLES 15 using the package manager.
    1. Install the CUDA repository public GPG key.
 $ distribution=$(. /etc/os-release;echo $ID$VERSION_ID | sed -e 's/\.[0-9]//')



    2. Setup the CUDA network repository.
 $ sudo zypper ar http://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-$distribution.repo



    3. If not already done, activate the SUSE Package Hub with SUSEConnect. On OpenSUSE systems, this step can be skipped.
 $ sudo SUSEConnect  -p PackageHub/15.1/x86_64



    4. Update the repository cache.
 $ sudo zypper refresh



The NVIDIA driver requires that the kernel headers and development packages for the running version of the kernel be installed at the time of the driver installation, as well whenever the driver is rebuilt. For example, if your system is running kernel version 4.4.0, the 4.4.0 kernel headers and development packages must also be installed.
 For SUSE, ensure that the system has the correct Linux kernel sources from the SUSE repositories.
 Use the output of the uname command to determine the running kernel's version and variant:

 $ uname -r 
    5. 4.12.14-lp151.27-default
 In this example, the version is 4.12.14-lp151.27 and the variant is default. The kernel headers and development packages can then be installed with the following command, replacing <variant> and <version> with the variant and version discovered from the previous uname command:
 $ sudo zypper install -y kernel-<variant>-devel=<version>



    6. Proceed to install the driver using the cuda-drivers meta-package.
 $ sudo zypper install -y cuda-drivers



    7. On SUSE systems, add the user to the video group.
 $ sudo usermod -a -G video <username>



    8. A reboot of the system may be required to verify that the NVIDIA driver modules are loaded and the devices visible under /dev.
 $ sudo reboot
================
Latest drivers (2-23-24)


==



=========
2nd cluster with 2 workers and 3 GPUs total
