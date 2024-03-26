# Installing SLES on Nvidia DPU 

**in progress, don't use for any references**

## Installing SLES on Nvidia BlueField-2 card

Review (https://github.com/Mellanox/bfb-build/) and modify a bfb-build and a DOCKER file with proper values.

If installing OS from the host, install *rshim* on the host and enable it.

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

On the host machine:

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
Make sure that your host node has *picocom* or *minicom* installed to access a DPU through rshim.

From DPU's uefi disable secure boot.
````
picocom /dev/rshim0/console
````
where rshim0 is the proper DPU.

In this test example a host node has 3 DPUs installed, so should have 3 rshim devices listed:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d5b92529-164e-4659-978c-061b0ce9e0be)


Modify a Dockerfile and bfb-build file according to your OS release.

install a podman

````
zypper in podman
````


To build a .bfb image run  

````
./bfb-build
````
that will create an image in the */tmp/distro/version.pid* directory

To install an image to DPU run

````
 echo "SW_RESET 1" > /dev/rshim0/misc
````
which should reset a DPU device and


````
./bfb-install -b /tmp/leap15.5.72330/leap.bfb -r rshim0
````
to push an image to DPU.


> [!NOTE]
> These steps validated only for BlueField-2
> For BlueField-3 this installation method should become available with SP6.



![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3f2776a1-9ed3-4a7e-a979-e6fe8f0f6503)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ce27a886-9f3c-46a8-8dbd-ee39348b4f9d)

If MLNX_OFED drivers are not included in your Dockerfile definition download MLNX_OFED drivers from (https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/) and install on DPU to enable fast interface.

Review [Installing MLNX_OFED](https://docs.nvidia.com/networking/display/mlnxofedv24010331/installing+mlnx_ofed)

untar downloaded package

tar xzf MLNX_OFED_LINUX-23.10-1.1.9.0-sles15sp5-aarch64.tgz

 ./mlnxofedinstall 
 

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


**Creating an RKE2 cluster**

From Rancher manager, click *Create* RKE2 custom cluster


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d363b591-be3d-4350-8666-ff5fcd52d062)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/1d6efc0a-e1f0-457a-9073-695efdb75801)


From the *Registration* tab provide a proper value for the node and roles which you are planning to add to the cluster.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/397011ae-90b8-4de2-ad6e-4eaefa2a4424)


Copy a registration command and paste to the terminal of the new node.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/35b382ec-ccb1-4cd7-9d25-875e01396264)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/1f2570df-04dd-43b8-8574-f39f94249446)


Do the same for other nodes which you are adding to the RKE2 cluster.




