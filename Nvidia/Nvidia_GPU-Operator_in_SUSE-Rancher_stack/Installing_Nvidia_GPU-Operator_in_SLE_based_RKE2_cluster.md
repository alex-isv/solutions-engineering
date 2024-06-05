# Deploying Nvidia GPU-Operator in SUSE based RKE2 cluster

## Purpose
These steps outlines installation of Nvidia gpu-operator in SUSE Kubernetes cluster with SLES based worker nodes and a Rancher server for easy deployment and management.
> [!NOTE]
> These steps are validated by SUSE, however are not officially supported by any sides.
> For more details on the support, please contact Nvidia.

## Prerequisites

<ins> Setup environment </ins>

In this test SUSE HARVESTER cluster 1.2.1 with SLE15.5 VMs was used as a base RKE2 cluster and physical SLES based worker nodes with Nvidia GPU installed.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9dfe7c00-8055-4290-8365-d38fbe8cb03f)


You can also integrate a Rancher server with a Harvester cluster for easy cluster management (https://docs.harvesterhci.io/v1.2/rancher/index)


> [!NOTE]
> Verify a support matrix before the installation  (https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-8-2/)

  Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster with a Rancher manager.
  

- **Install GPU drivers on the worker node**

> [!TIP]
> Before installing new drivers, make sure to remove older versions of CUDA Toolkit and Nvidia drivers:
````
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"
````

````
sudo zypper remove "*nvidia*"
````

 
Review steps from (https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/index.html#suse15)


This section includes instructions for installing the NVIDIA driver on SLES 15 using the package manager.\

1. Install the CUDA repository public GPG key.
    
````
distribution=$(. /etc/os-release;echo $ID$VERSION_ID | sed -e 's/\.[0-9]//')
````
2. Setup the CUDA network repository.
    
````
sudo zypper ar http://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-$distribution.repo
````

3. If not already done, activate the SUSE Package Hub with SUSEConnect.
    
````
sudo SUSEConnect  -p PackageHub/15.4/x86_64
````
4. Update the repository cache.
    
````
sudo zypper refresh
````

>The NVIDIA driver requires that the kernel headers and development packages for the running version of the kernel be installed at the time of the driver installation, as well whenever the driver is rebuilt. For example, if your system is running kernel version 4.4.0, the 4.4.0 kernel headers and development packages must also be installed.
 For SUSE, ensure that the system has the correct Linux kernel sources from the SUSE repositories.
>
>
5. Use the output of the uname command to determine the running kernel's version and variant:

````
uname -r 
````
>5.14.21-150500.55.49-default
>
 > In this example, the version is 5.14.21-150500.55.49 and the variant is default. The kernel headers and development packages can then be installed with the following command, replacing <variant> and <version> with the variant and version discovered from the previous uname command:
>
````
sudo zypper install -y kernel-<variant>-devel=<version>
````

6. Proceed to install the driver using the cuda-drivers meta-package.
````
sudo zypper install -y cuda-drivers
````
7. On SUSE systems, add the user to the video group.
 ````
sudo usermod -a -G video <username>
````

8. A reboot of the system may be required to verify that the NVIDIA driver modules are loaded and the devices visible under /dev.
````
sudo reboot
````

For more details on the available distros review - (https://developer.download.nvidia.com/compute/cuda/repos/sles15/)


Verify that nvidia-smi command is working on the **worker** node.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c9451823-4e60-4989-8c90-3bd34dac640d)





## Install a gpu-operator with helm command:

````
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
  --set toolkit.version=v1.15.0-ubi8  \
  --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
  --set-string validator.driver.env[0].value=true
````

> [!NOTE]
> In this particular scenario GPU drivers installed on the worker node, so `driver.enabled` value should be set to `false` when installing with helm.
> If using a custom container driver for SLE based system on the local or public registry, review steps [Building the container image](https://documentation.suse.com/trd/kubernetes/pdf/gs_rke2-slebci_nvidia-gpu-operator_en.pdf).
> 
> Please be aware, that steps for building a container based driver were tested for specific versions, so any <ins>new versions</ins> of gpu-operator, container toolkit or Go, should be re-validated again.


Verify that gpu-operator was installed:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d0577239-88f1-44b5-94d7-71509b958a58)


Check that `driver-validation`, `cuda-validation` and `toolkit-validation` passed.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/dd1b4d19-50a8-4462-8618-2afabb9f48c9)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/6dc60128-b09f-4456-a5bc-449cee6d704b)

or from the master node you can check logs as well:

````
kubectl logs -n gpu-operator -l app=nvidia-operator-validator
````
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/14da7bf1-62c1-497d-8911-b061fd140c20)



For the testing purpose on the 2nd cluster I added 2 worker nodes with 3 GPUs total:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/96a87968-b9f6-4885-b9e8-7fadc7668c0a)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ff8c352f-1c46-410a-842c-6887552b9d52)
> 2 worker nodes with 1 x A100 80Gb and 2 x A100 40Gb
>
> 

- **Bringing a workload**

From the Rancher Dashboard click <int>Import Yaml</int> and paste the following:

````

apiVersion: v1
kind: Pod
metadata:
  name: tf-benchmarks
spec:
  restartPolicy: Never
  containers:
    - name: tf-benchmarks
      image: "nvcr.io/nvidia/tensorflow:23.10-tf2-py3"
      command: ["/bin/sh", "-c"]
      args: ["cd /workspace && git clone https://github.com/tensorflow/benchmarks/ && cd /workspace/benchmarks/scripts/tf_cnn_benchmarks && python tf_cnn_benchmarks.py --num_gpus=1 --batch_size=64 --model=resnet50 --use_fp16"]
      resources:
        limits:
          nvidia.com/gpu: 1
````

For the reference review > [MIG options section](https://developer.nvidia.com/blog/getting-kubernetes-ready-for-the-a100-gpu-with-multi-instance-gpu/) which can be used for different Nvidia tests including different MIG strategy.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/adbf20d9-4ab8-40c4-83cd-0366bc72b933)




![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/38ea6c87-290a-409c-aa86-80e89faac41c)


or check with command 

````
kubectl logs tf-benchmarks
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/98918319-932b-4832-91a1-cc421c7f286a)


To visualize a workload review a [GPU metrics with Grafana](https://github.com/alex-isv/solutions-engineering/blob/main/Nvidia/Nvidia-DGX/adoc/Nvidia_DGX_on_SUSE-Rancher_stack.md#review-gpu-metrics)



