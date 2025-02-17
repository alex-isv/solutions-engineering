# Deployment steps for AMD GPU in SUSE/Rancher Kubernetes stack

## Purpose 
These steps outlines installation of AMD GPU Device Plugin in SUSE RKE2 Kubernetes cluster and managed by a Rancher server.

## Prerequisites

Please review [AMD GPU device plugin for Kubernetes](https://github.com/ROCm/k8s-device-plugin#amd-gpu-device-plugin-for-kubernetes).

<ins> Setup environment </ins>

- SLES 15 sp5 based RKE2 cluster with a Rancher manager. Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster.

 ![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/7f7ea5ad-2041-44e9-9bac-adead5843646)

In the above example, the RKE2 6 nodes cluster is shown from the Rancher console.

- MI210 AMD GPU installed in the worker node.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/2f211fdd-79c0-4fef-b395-18afa106d47b)



  ## Install ROCM on the worker (GPU) node.

 Install ROCM on the worker node as per ROCm documentation [SUSE Linux Enterprise native installation](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/tutorial/quick-start.html) section.

````
sudo zypper addrepo https://download.opensuse.org/repositories/devel:languages:perl/15.5/devel:languages:perl.repo

sudo zypper install kernel-default-devel
sudo usermod -a -G render,video $LOGNAME # Adding current user to Video, Render groups. See prerequisites.
sudo zypper --no-gpg-checks install https://repo.radeon.com/amdgpu-install/6.1.2/sle/15.5/amdgpu-install-6.1.60102-1.noarch.rpm
sudo zypper refresh
sudo zypper install amdgpu-dkms
sudo zypper install rocm
````
Reboot a worker node.

> [!NOTE]
> Secure boot should be disabled from BIOS.
> 
Verify ROCm installation by running
````
./clinfo
````
or
````
./rocminfo
````
from the installation directory

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/b70e4f44-b0fd-4258-b4c6-11a0dc778d25)


## Install a GPU device plugin

Open a Rancher RKE2 cluster, go to Apps - Charts from the left console.

Select All from the Charts and search for AMD.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e772400a-4e1a-4b6f-9332-505bd497d693)


Click on **AMD GPU Device Plugin** helm chart to install.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e725ad23-42d7-4194-b0c8-7e4f46cbd26e)

Review [AMD GPU labeller](https://github.com/ROCm/k8s-device-plugin/blob/master/cmd/k8s-node-labeller/README.md#amd-gpu-kubernetes-node-labeller) section for a proper node labels for a GPU node.

You can either install sample yaml file [k8s-ds-amdgpu-labeller.yaml](https://github.com/ROCm/k8s-device-plugin/blob/master/k8s-ds-amdgpu-labeller.yaml)
with

````
kubectl create -f https://github.com/ROCm/k8s-device-plugin/blob/master/k8s-ds-amdgpu-labeller.yaml
````

or manually add proper labels from the Rancher cluster node section.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c23f014e-d7bd-4def-b76f-f969aa622bd7)


## Bring some test workload

Select <ins>Import yaml</ins> and add a test workload contents.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5237d315-e961-4ecc-8c41-d0a71ad012b7)


In this particular example Tensorflow with inception3 model was used.

Container should be created and workload verified from logs.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/7f57162a-e88d-43e2-a1d7-48f230790be3)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/2e7089c1-a0a7-41a8-9e84-fd17fa89092f)

or from the Master node run 
````
cl2-vm1:/var/lib/rancher/rke2/bin # ./kubectl logs benchmark-gpu -n amd-plugin
````
to verify 

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3cb42bdf-aaf4-4433-9b2c-74e651f45cff)






