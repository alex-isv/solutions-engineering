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
````
zypper in helm
````

Install k3s
 
Verify the last certified version >> (https://github.com/k3s-io/k3s/releases)

````
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.10+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
````

````
k3s kubectl get nodes
````
>
> NAME          STATUS   ROLES                       AGE   VERSION
>
> cl2-rancher   Ready    control-plane,etcd,master   86s   v1.27.10+k3s1


````
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
````

 Install Rancher with helm

 ````
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable \
kubectl create namespace cattle-system 
````
````
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml \
helm repo add jetstack https://charts.jetstack.io \
helm repo update
````
````
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
````

````
kubectl get pods --namespace cert-manager
````
>
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5dcc4c9b74-8rqtt              1/1     Running   0          34s
cert-manager-cainjector-644bff8d57-tn7t6   1/1     Running   0          34s
cert-manager-webhook-7f6b4fbd47-kv6pn      1/1     Running   0          34s
Verify a certified Rancher version > https://github.com/rancher/rancher/tags
>

````
 helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=cl2-rancher.isv.suse --set version=2.8.2 --set replicas=1
````


Login to Rancher URL in the browser and change a password.

**Create RKE2 cluster**


From Rancher server go to the Cluster Management and select RKE2 and click Custom

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/cadd344c-a1d4-4063-b1d7-308ffb3bdf14)



Click <Create> and select a proper roles and additional settings

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e807b946-b46c-475b-9540-281d84e4eeef)



Copy a registration command and paste into the terminal of the node which are you are planning to add to the cluster.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/89149d32-8b5a-4d78-9630-6bf41a716772)



Make sure that you have the odd number of nodes in the cluster.\
Add a worker node with a <ins>GPU</ins> installed.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/8c715829-9da4-48e6-ae45-a261b4a4c2bf)



> cl2-vm1:/var/lib/rancher/rke2/bin # ./kubectl get nodes
NAME      STATUS   ROLES                       AGE     VERSION
cl2-vm1   Ready    control-plane,etcd,master   6m56s   v1.27.10+rke2r1
cl2-vm2   Ready    control-plane,etcd,master   11m     v1.27.10+rke2r1
cl2-vm4   Ready    control-plane,etcd,master   6m23s   v1.27.10+rke2r1
r750-a    Ready    worker                      6m6s    v1.27.10+rke2r1
> 



**Install GPU drivers on the worker node**

> [!TIP]
> Before installing new drivers, make sure to remove CUDA Toolkit:
> ````
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"
````

and remove NVIDIA Drivers:
````
sudo zypper remove "*nvidia*"
````
>
>
 
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

    3. If not already done, activate the SUSE Package Hub with SUSEConnect. On OpenSUSE systems, this step can be skipped.
````
sudo SUSEConnect  -p PackageHub/15.1/x86_64
````

    4. Update the repository cache.
````
sudo zypper refresh
````

>The NVIDIA driver requires that the kernel headers and development packages for the running version of the kernel be installed at the time of the driver installation, as well whenever the driver is rebuilt. For example, if your system is running kernel version 4.4.0, the 4.4.0 kernel headers and development packages must also be installed.
 For SUSE, ensure that the system has the correct Linux kernel sources from the SUSE repositories.
>
>
 Use the output of the uname command to determine the running kernel's version and variant:

````
uname -r 
````

    5. 5.14.21-150500.55.49-default
 In this example, the version is 5.14.21-150500.55.49 and the variant is default. The kernel headers and development packages can then be installed with the following command, replacing <variant> and <version> with the variant and version discovered from the previous uname command:
 ````
sudo zypper install -y kernel-<variant>-devel=<version>
````

    6. Proceed to install the driver using the cuda-drivers meta-package.
````
sudo zypper install -y cuda-drivers
````

    7. On SUSE systems, add the user to the video group.
 $ sudo usermod -a -G video <username>


    8. A reboot of the system may be required to verify that the NVIDIA driver modules are loaded and the devices visible under /dev.
````
sudo reboot
````

Verify that nvidia-smi command is working on the **worker** node.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3d71fbb0-e883-4c15-80da-e51f64764a3b)




## Install gpu-operator with helm command:

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
  --set toolkit.version=v1.14.5-centos7 \
  --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
  --set-string validator.driver.env[0].value=true
````

> [!NOTE]
> In this particular scenario GPU drivers installed on the worker node, so `driver.enabled` value should be set to `false` when installing with helm.


Verify that gpu-operator was installed:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/dd1b4d19-50a8-4462-8618-2afabb9f48c9)



Adding a 2nd worker node to cluster:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/96a87968-b9f6-4885-b9e8-7fadc7668c0a)



> 2 worker nodes with 1 x A100 80Gb and 2 x A100 40Gb


**Bringing a workload**


