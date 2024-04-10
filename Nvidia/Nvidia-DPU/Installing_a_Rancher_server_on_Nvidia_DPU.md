# Installing a Rancher server on NVIDIA BlueField device#
**Installing a Rancher server on DPU** 

*Proof of concept. Don't use as an official reference*


> [!NOTE]
> ARM64 is the experimental version and is not officially supported.
> Verify a support option with a SUSE/RANCHER team.

Check releases > (https://github.com/k3s-io/k3s/releases) and make sure that k3s version supports a Rancher server release. 

The below commands can be use for SLES and MICRO.

1. curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.11+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
2. export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
3. helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
4. kubectl create namespace cattle-system
5. kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml
6. helm repo add jetstack https://charts.jetstack.io
7. helm repo update
8. helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
9. kubectl get pods --namespace cert-manager
10. helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=dpu1.isv.suse --set version=2.8.2 --set replicas=1


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9fba1dff-a66c-423d-b4cd-e9324e1b79f7)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/855c1ddf-ce04-4d3f-a2ff-5ae4df36766f)

 ![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/76aa22ee-1179-4339-8ae7-c790121f1759)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e090fb51-452e-4d8d-a373-239f1c552943)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ee000619-45d3-4533-b79e-3b1d04e696ae)


**Creating an RKE2 cluster**

From Rancher manager, click *Create* RKE2 custom cluster


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/87c76d69-5db8-48ee-bea1-7abb38252e02)



From the *Registration* tab provide a proper value for the node and roles which you are planning to add to the cluster.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/397011ae-90b8-4de2-ad6e-4eaefa2a4424)


Copy a registration command and paste to the terminal of the new node.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/35b382ec-ccb1-4cd7-9d25-875e01396264)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/1f2570df-04dd-43b8-8574-f39f94249446)


Do the same for other nodes which you are adding to the RKE2 cluster.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/622aaade-51f3-43ef-aca9-3d86a39097ea)


Example from the existing cluster with 2 DPUs and a worker node with Nvidia GPU.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c8d8ca88-1257-4a30-bdcf-05edc25bc3de)
