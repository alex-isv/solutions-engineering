# Installing SLES on Nvidia DPU 
**in progress, don't use for any references**

## Installing SLES on Nvidia BlueField-2 card

Review (https://github.com/Mellanox/bfb-build/) and modify a DOCKER file with proper values.

If installing OS from the host, install rshim on the host and enable it.

````
zypper in rshim
````
````
systemctl enable rshim
````

````
systemctl start rshim
````

verify that rshim is running

````
systemctl status rshim
````

For Arm systems >>

````
wget https://www.mellanox.com/downloads/DOCA/DOCA_v2.5.0/doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.aarch64.rpm
````
````
rpm -Uvh doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.aarch64.rpm
````
````
zypper refresh 

````

````
sudo zypper install doca-ofed
````

For x86 >>

````
wget https://www.mellanox.com/downloads/DOCA/DOCA_v2.5.0/doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.x86_64.rpm
````
````
rpm -Uvh doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.x86_64.rpm
````
````
zypper refresh
````
````
sudo zypper install doca-ofed
````

Clone a bfb-build from Mellanox git page.

````
git clone https://github.com/Mellanox/bfb-build
````

````
cd bfb-build
````

Modify a Dockerfile and bfb-build file according to your OS release.

build .bfb image 

````
./bfb-build
````



![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3f2776a1-9ed3-4a7e-a979-e6fe8f0f6503)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ce27a886-9f3c-46a8-8dbd-ee39348b4f9d)

Download MLNX_OFED drivers from (https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/) and install on DPU to enable fast interface.
Review [Installing MLNX_OFED](https://docs.nvidia.com/networking/display/mlnxofedv24010331/installing+mlnx_ofed)

untar downloaded package

tar -xzf MLNX_OFED_SRC-<debian?>-<version>.tgz

 ./mlnxofedinstall --without-fw-update
 
Need to untar and run mlnxofedinstall script 

 zypper remove mlxbf-bfscripts


**Installing a Rancher server on DPU**

> [!NOTE]
> ARM64 is the experimental version and not supported.
> Verify a support option with a SUSE/RANCHER team.

Check releases > (https://github.com/k3s-io/k3s/releases) and make sure that k3s version supports a Rancher server release. 



1. zypper in helm
2. curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.11+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
3. export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
4. helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
5. kubectl create namespace cattle-system
6. kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml
7. helm repo add jetstack https://charts.jetstack.io
8. helm repo update
9. helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
10. kubectl get pods --namespace cert-manager
11. helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=dpu1.isv.suse --set version=2.8.2 --set replicas=1


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9fba1dff-a66c-423d-b4cd-e9324e1b79f7)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/855c1ddf-ce04-4d3f-a2ff-5ae4df36766f)

 ![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/76aa22ee-1179-4339-8ae7-c790121f1759)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e090fb51-452e-4d8d-a373-239f1c552943)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ee000619-45d3-4533-b79e-3b1d04e696ae)


