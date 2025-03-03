# Deploying Nvidia DPU-operator in Suse/Rancher cluster.

> [!NOTE]
> Work in progress. Don't use as a reference.
> 

## Use case

[**Host based networking.**](https://github.com/NVIDIA/doca-platform/tree/release-v25.1/docs/guides/usecases/hbn_only#deploy-test-pods)


### Prerequisites ###

RKE2 cluster description here...

<diagram>

<ins> 3 SLES 15sp6 admin nodes </ins> 

<ins> 2 worker nodes hosting BF-3 cards connected to a high-speed switch. </ins> 

managed by a Rancher server.

Follow these [steps](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md) to install a Rancher with RKE2.

For this particular test, add 2 control-plane nodes to the cluster and 1 node with all roles assigned to complete a cluster creation.

Use, <ins> multus,cilium CLI combo </ins> during the cluster creation.

![image](https://github.com/user-attachments/assets/ca2a816f-01e4-43db-840f-7a9fd1666388)


Don't add worker nodes with BF-3 cards installed to the cluster at the beginning.

Setup a networking for worker nodes as described [here](https://github.com/NVIDIA/doca-platform/blob/release-v25.1/docs/guides/usecases/host-network-configuration-prerequisite.md).

Create a variables file on the admin node <ins> export_vars.env </ins> as described [here](https://github.com/NVIDIA/doca-platform/tree/release-v25.1/docs/guides/usecases/hbn_only#0-required-variables) and source the file as

````
source export_vars.env
````

### DPF Operator installation

````
kubectl create namespace dpf-operator-system
````

Clone dpf-operator registry.

````
git clone https://github.com/NVIDIA/doca-platform.git
````

````
cd ..doca-platform/docs/guides/usecases/hbn_only
````

**Install cert-manager**

````
helm repo add jetstack https://charts.jetstack.io --force-update
````


````
helm upgrade --install --create-namespace --namespace cert-manager cert-manager jetstack/cert-manager --version v1.16.1 -f ./manifests/01-dpf-operator-installation/helm-values/cert-manager.yml
````

**Install a CSI to back the DPUCluster etcd**

````
curl https://codeload.github.com/rancher/local-path-provisioner/tar.gz/v0.0.30 | tar -xz --strip=3 local-path-provisioner-0.0.30/deploy/chart/local-path-provisioner/

kubectl create ns local-path-provisioner

helm install -n local-path-provisioner local-path-provisioner ./local-path-provisioner --version 0.0.30 -f ./manifests/01-dpf-operator-installation/helm-values/local-path-provisioner.yml
````

**Create secrets and storage required by the DPF Operator**

````
cat manifests/01-dpf-operator-installation/*.yaml | envsubst | kubectl apply -f -
````

**Deploy the DPF Operator**

````
envsubst < ./manifests/01-dpf-operator-installation/helm-values/dpf-operator.yml | helm upgrade --install -n dpf-operator-system dpf-operator $REGISTRY --version=$TAG --values -
````

Verify workloads and pods deployed:


![image](https://github.com/user-attachments/assets/2b57ec56-8002-4e60-be0e-18d5f66a92d8)


![image](https://github.com/user-attachments/assets/32bd4a46-b05e-4071-a0ad-b9131f559249)


![image](https://github.com/user-attachments/assets/85b4546b-532d-42a1-b1e5-ab12947a3722)


### DPF system installation



````
kubectl create ns dpu-cplane-tenant1

cat manifests/02-dpf-system-installation/*.yaml | envsubst | kubectl apply -f -
````


![image](https://github.com/user-attachments/assets/1ece073d-ebd6-4a08-881c-872600ad5950)


Validate with:

````
kubectl rollout status deployment --namespace dpf-operator-system dpf-provisioning-controller-manager dpuservice-controller-manager

````


![image](https://github.com/user-attachments/assets/f0e0d5a3-4cd4-48bf-a56d-61e7470b40a0)



### Enable accelerated interfaces

**Install Multus and SRIOV Network Operator using NVIDIA Network Operator**

````
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update

helm upgrade --no-hooks --install --create-namespace --namespace nvidia-network-operator network-operator nvidia/network-operator --version 24.7.0 -f ./manifests/03-enable-accelerated-interfaces/helm-values/network-operator.yml
````

**Apply the NICClusterConfiguration and SriovNetworkNodePolicy**

````
cat manifests/03-enable-accelerated-interfaces/*.yaml | envsubst | kubectl apply -f -
````

Verify installation.

![image](https://github.com/user-attachments/assets/1d634722-0c0e-4f50-91ad-a5738f548f13)


#### DPU Provisioning and Service Installation

**With DPUDeployment**

````
cat manifests/04.2-dpudeployment-installation/*.yaml | envsubst | kubectl apply -f -
````

**Verify with:**

````
kubectl wait --for=condition=ApplicationsReconciled --namespace dpf-operator-system  dpuservices hbn-only-doca-hbn
````

![image](https://github.com/user-attachments/assets/9b2b7468-9dd2-488c-b595-b37228789a1a)

At this point NFS server should list <ins> .bfb file </ins>.

<ins>
nv-2:/mnt/dpf_share/bfb # ls
dpf-operator-system-bf-bundle.bfb
</ins>


Add DPU worker nodes to the cluster.

![image](https://github.com/user-attachments/assets/ba2a8dbe-0001-4b93-93f9-40693a55ffd5)



**Test traffic**

````
kubectl apply -f manifests/05-test-traffic
````

That will deploy 2 test pods.

Use iperf3 to test networking between two pods.


