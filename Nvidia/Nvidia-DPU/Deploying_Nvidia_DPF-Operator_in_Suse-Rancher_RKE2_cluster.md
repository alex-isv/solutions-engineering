# Deploying Nvidia DPU-operator in Suse/Rancher cluster.

> [!NOTE]
> Proof of concept. Don't use as a reference.
> 

## Use case

Review Nvidia DOCA platform operator (DPF) for [**Host based networking**](https://github.com/NVIDIA/doca-platform/tree/release-v25.1/docs/guides/usecases/hbn_only#deploy-test-pods) usecase.

For SUSE TELCO/ATIP concept review [SUSE Edge for Telco Architecture](https://documentation.suse.com/suse-edge/3.2/single-html/edge/#atip-architecture).

### Prerequisites ###


![image](https://github.com/user-attachments/assets/b0429626-095b-4252-9875-d8e6311e2a1d)


Demo RKE2 cluster with:

<ins> 3 admin nodes (SLES-15sp6 based) </ins> 

<ins> 2 worker nodes hosting BF-3 cards connected to a high-speed switch. </ins> 

provisioned and managed by a Rancher server.

Follow these [steps](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md) to install a Rancher with RKE2.

For this particular test, add 2 control-plane nodes to the cluster and 1 node with all roles assigned to complete a cluster creation.

Any, Multus/CNI combo can be used during the cluster creation.

![image](https://github.com/user-attachments/assets/e22172e5-3005-42b9-bab5-95c917063cd3)



![image](https://github.com/user-attachments/assets/5dfa95f1-6a71-4a31-95e3-85b8e6fe023c)

> [!NOTE]
> If using *cilium/multus* combo cni from Rancher deployment, you need to set cni option to *exclusive: false* in the cilium config.
>
> 

<ins> Don't add worker nodes with BF-3 cards installed to the cluster at this point, as they should be added after all configuration complete.</ins>

Setup a networking for worker nodes as described [here](https://github.com/NVIDIA/doca-platform/blob/release-v25.1/docs/guides/usecases/host-network-configuration-prerequisite.md).

For ex. worker node should have a bridge configured throgh the management interface:

![image](https://github.com/user-attachments/assets/13061249-a0de-47cb-b201-5caec1fd2763)

and the bridge routing should go through default gateway:

![image](https://github.com/user-attachments/assets/270ba10b-a467-4bbd-a121-262921948eeb)

Fast speed interfaces should be set to DHCP.

Cumulus 200Gb/s switch configuration example:

Ports: 11, 12, 13, 14 are used to connect DPUs.

````
nv set evpn enable on
nv set interface lo ip address 11.0.0.101/32
nv set interface lo type loopback
nv set interface swp11-14 type swp
nv set nve vxlan enable on
nv set qos roce enable on
nv set qos roce mode lossless
nv set router bgp autonomous-system 65001
nv set router bgp enable on
nv set router bgp graceful-restart mode full
nv set router bgp router-id 11.0.0.101
nv set vrf default router bgp address-family ipv4-unicast enable on
nv set vrf default router bgp address-family ipv4-unicast redistribute connected enable on
nv set vrf default router bgp address-family ipv4-unicast redistribute static enable on
nv set vrf default router bgp address-family ipv6-unicast enable on
nv set vrf default router bgp address-family ipv6-unicast redistribute connected enable on
nv set vrf default router bgp address-family l2vpn-evpn enable on
nv set vrf default router bgp enable on
nv set vrf default router bgp neighbor swp11 peer-group hbn
nv set vrf default router bgp neighbor swp11 type unnumbered
nv set vrf default router bgp neighbor swp12 peer-group hbn
nv set vrf default router bgp neighbor swp12 type unnumbered
nv set vrf default router bgp neighbor swp13 peer-group hbn
nv set vrf default router bgp neighbor swp13 type unnumbered
nv set vrf default router bgp neighbor swp14 peer-group hbn
nv set vrf default router bgp neighbor swp14 type unnumbered
nv set vrf default router bgp path-selection multipath aspath-ignore on
nv set vrf default router bgp peer-group hbn address-family l2vpn-evpn enable on
nv set vrf default router bgp peer-group hbn remote-as external

````

Create a variables file on the admin node <ins> export_vars.env </ins> as described [here](https://github.com/NVIDIA/doca-platform/tree/release-v25.1/docs/guides/usecases/hbn_only#0-required-variables) and source the file as

<details><summary>Expand for detailed helm values</summary>
````
## IP Address for the Kubernetes API server of the target cluster on which DPF is installed.
## This should never include a scheme or a port.
## e.g. 10.10.10.10
export TARGETCLUSTER_API_SERVER_HOST=192.168.143.22
 # where 192.168.143.22 is a control-plane node

## Port for the Kubernetes API server of the target cluster on which DPF is installed.
export TARGETCLUSTER_API_SERVER_PORT=6443
  
## Virtual IP used by the load balancer for the DPU Cluster. Must be a reserved IP from the management subnet and should not be allocated by DHCP.
export DPUCLUSTER_VIP=192.168.143.100
 # any available IP from the management 1gb network.

## DPU_P0 is the name of the first port of the DPU. This name must be the same on all worker nodes.
export DPU_P0=p2p1
 
 
## Interface on which the DPUCluster load balancer will listen. Should be the management interface of the control plane node.
export DPUCLUSTER_INTERFACE=eth0
 
# IP address to the NFS server used as storage for the BFB.
export NFS_SERVER_IP=192.168.143.4
# above if the nv-2 node which is part of the cluster, 2nd control-plane/etcd node
#

## The repository URL for the NVIDIA Helm chart registry.
## Usually this is the NVIDIA Helm NGC registry. For development purposes, this can be set to a different repository.
export NGC_HELM_REGISTRY_REPO_URL=https://helm.ngc.nvidia.com/nvidia/doca


## The repository URL for the HBN container image.
## Usually this is the NVIDIA NGC registry. For development purposes, this can be set to a different repository.
export HBN_NGC_IMAGE_URL=nvcr.io/nvidia/doca/doca_hbn


# API key for accessing containers and helm charts from the NGC private repository.
export NGC_API_KEY=YOUR-NGC-KEY-generated-from-NGC-accounnt
 
 
## The DPF REGISTRY is the Helm repository URL for the DPF Operator.
## Usually this is the GHCR registry. For development purposes, this can be set to a different repository.
export REGISTRY=oci://ghcr.io/nvidia/dpf-operator


## The DPF TAG is the version of the DPF components which will be deployed in this guide.
export TAG=v25.1.0


## URL to the BFB used in the `bfb.yaml` and linked by the DPUSet.
export BLUEFIELD_BITSTREAM="https://content.mellanox.com/BlueField/BFBs/Ubuntu22.04/bf-bundle-2.9.1-40_24.11_ubuntu-22.04_prod.bfb"
````
</details>


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


![image](https://github.com/user-attachments/assets/fedb3529-78a0-4fda-8d65-7a58acdeb077)




![image](https://github.com/user-attachments/assets/85b4546b-532d-42a1-b1e5-ab12947a3722)


### DPF system installation



````
kubectl create ns dpu-cplane-tenant1

cat manifests/02-dpf-system-installation/*.yaml | envsubst | kubectl apply -f -
````


![image](https://github.com/user-attachments/assets/8badbb61-07d7-40fe-b3d8-ac00c53f216c)


Validate with:

````
kubectl rollout status deployment --namespace dpf-operator-system dpf-provisioning-controller-manager dpuservice-controller-manager

````


![image](https://github.com/user-attachments/assets/9b0a7781-fd3c-453c-bbab-22ab32faaad8)



### Enable accelerated interfaces

**Install SRIOV using NVIDIA Network Operator**

````
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update

helm upgrade --no-hooks --install --create-namespace --namespace nvidia-network-operator network-operator nvidia/network-operator --version 24.7.0 -f ./manifests/03-enable-accelerated-interfaces/helm-values/network-operator.yml
````

> [!NOTE]
> Since RKE2 cluster created initially with Multus, the section in *nic_cluster_policy.yaml* file should remove multus option from upstream and
>  include only:
> 
> ````
> apiVersion: mellanox.com/v1alpha1
> kind: NicClusterPolicy
> metadata:
>   name: nic-cluster-policy
> spec:
>   secondaryNetwork:
> ````
>
> *sriov_network_operator_polity.yaml* should have the following setting based on the device names on the worker nodes:


<details><summary>Expand for detailed helm values</summary>
  
````yml
---
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: bf3-p0-vfs
  namespace: nvidia-network-operator
spec:
  mtu: 1500
  nicSelector:
    deviceID: "a2dc"
    vendor: "15b3"
    pfNames:
    - p2p1#2-45
    - p5p1#2-45
  nodeSelector:
    node-role.kubernetes.io/worker: ""
  numVfs: 46
  resourceName: bf3-p0-vfs
  isRdma: true
  externallyManaged: true
  deviceType: netdevice
  linkType: eth
````
  </details>



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

*nv-2:/mnt/dpf_share/bfb # ls*
  
*dpf-operator-system-bf-bundle.bfb*




**Add DPU worker nodes to the cluster.**

> [!NOTE]
> For this Demo test.
> Add a label *feature.node.kubernetes.io/dpu-oob-bridge-configured*
> and *node-role.kubernetes.io/worker* with the **empty** values in the worker node.
> That is needed due to the conflict on how RKE2 labeling nodes with a 'true' value by default and values in the config yaml files.

![image](https://github.com/user-attachments/assets/b4cb883b-fd9f-44d6-9045-f091b8890762)


Run command to check the DPU installation status:

````
watch -d "kubectl describe dpu -n dpf-operator-system | grep 'Node Name\|Type\|Last\|Phase'"

````


![image](https://github.com/user-attachments/assets/417d9302-8db6-44c3-be35-5f37789b7c49)

Node should be rebooted upon successfull installation.

You can also check dms pod logs if it's ready.

![image](https://github.com/user-attachments/assets/792c9857-5859-4a63-ac30-8cf0891e8b4a)


![image](https://github.com/user-attachments/assets/5445bbbd-3131-4192-987b-af2727bd5a9b)

Verify DPUServiceInterfaces:

![image](https://github.com/user-attachments/assets/8e1a5c02-627b-4f7a-bd48-188f7888e859)

Worker node should list newly created *VF* interfaces:

![image](https://github.com/user-attachments/assets/cea6534d-64dc-47d4-83d8-6d654e765838)


Add the 2nd worker and make sure that the 2nd DPU provisioned.

![image](https://github.com/user-attachments/assets/b25b26c9-49cd-4f15-9ee6-c3b3ecbff11a)



**Test traffic**

> [!NOTE]
> NAD-hostdev.yaml file should be created with the following settings:

<details><summary>Expand for detailed helm values</summary>
  
````yml

apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: hostdev-pf0vf10-worker1
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "hostpf0vf10",
    "type": "host-device",
    "device": "p2p1_10",
    "ipam": {
        "type": "static",
        "addresses": [
          {
            "address": "10.0.121.9/29"
          }
        ],
        "routes": [
          {
            "dst": "10.0.121.0/29",
            "gw": "10.0.121.10"
          }
        ]
    }
  }'
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: hostdev-pf1vf10-worker1
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "hostpf1vf10",
    "type": "host-device",
    "device": "p2p2_10",
    "ipam": {
        "type": "static",
        "addresses": [
          {
            "address": "10.0.122.9/29"
          }
        ],
        "routes": [
          {
            "dst": "10.0.122.0/29",
            "gw": "10.0.122.10"
          }
        ]
    }
  }'
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: hostdev-pf0vf10-worker2
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "hostpf0vf10",
    "type": "host-device",
    "device": "p5p1_10",
    "ipam": {
        "type": "static",
        "addresses": [
          {
            "address": "10.0.121.1/29"
          }
        ],
        "routes": [
          {
            "dst": "10.0.121.8/29",
            "gw": "10.0.121.2"
          }
        ]
    }
  }'
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: hostdev-pf1vf10-worker2
spec:
  config: '{
    "cniVersion": "0.3.1",
    "name": "hostpf1vf10",
    "type": "host-device",
    "device": "p5p2_10",
    "ipam": {
        "type": "static",
        "addresses": [
          {
            "address": "10.0.122.1/29"
          }
        ],
        "routes": [
          {
            "dst": "10.0.122.8/29",
            "gw": "10.0.122.2"
          }
        ]
    }
  }'
````
</details>


together with *test-hostdev-pods.yaml*



<details><summary>Expand for detailed helm values</summary>
  
````yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sriov-hostdev-pf0vf10-test-worker1
  labels:
    app: sriov-hostdev-pf0vf10-test-worker1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sriov-hostdev-pf0vf10-test-worker1
  template:
    metadata:
      labels:
        app: sriov-hostdev-pf0vf10-test-worker1
      annotations:
        k8s.v1.cni.cncf.io/networks: hostdev-pf0vf10-worker1
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: sriov-test-worker
      nodeSelector:
        feature.node.kubernetes.io/dpu-enabled: "true"
        kubernetes.io/hostname: "r750-a"
      containers:
      - name: nginx
        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
        image: nicolaka/netshoot
        command: ["nc", "-kl", "5000"]
        ports:
        - containerPort: 5000
          name: tcp-server
        resources:
          requests:
            cpu: 16
            memory: 6Gi
          limits:
            cpu: 16
            memory: 6Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sriov-hostdev-pf1vf10-test-worker1
  labels:
    app: sriov-hostdev-pf1vf10-test-worker1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sriov-hostdev-pf1vf10-test-worker1
  template:
    metadata:
      labels:
        app: sriov-hostdev-pf1vf10-test-worker1
      annotations:
        k8s.v1.cni.cncf.io/networks: hostdev-pf1vf10-worker1
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: sriov-test-worker
      nodeSelector:
        feature.node.kubernetes.io/dpu-enabled: "true"
        kubernetes.io/hostname: "r750-a"
      containers:
      - name: nginx
        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
        image: nicolaka/netshoot
        command: ["nc", "-kl", "5000"]
        ports:
        - containerPort: 5000
          name: tcp-server
        resources:
          requests:
            cpu: 16
            memory: 6Gi
          limits:
            cpu: 16
            memory: 6Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sriov-hostdev-pf0vf10-test-worker2
  labels:
    app: sriov-hostdev-pf0vf10-test-worker2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sriov-hostdev-pf0vf10-test-worker2
  template:
    metadata:
      labels:
        app: sriov-hostdev-pf0vf10-test-worker2
      annotations:
        k8s.v1.cni.cncf.io/networks: hostdev-pf0vf10-worker2
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: sriov-test-worker
      nodeSelector:
        feature.node.kubernetes.io/dpu-enabled: "true"
        kubernetes.io/hostname: "r7525-a"
      containers:
      - name: nginx
        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
        image: nicolaka/netshoot
        command: ["nc", "-kl", "5000"]
        ports:
        - containerPort: 5000
          name: tcp-server
        resources:
          requests:
            cpu: 16
            memory: 6Gi
          limits:
            cpu: 16
            memory: 6Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sriov-hostdev-pf1vf10-test-worker2
  labels:
    app: sriov-hostdev-pf1vf10-test-worker2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sriov-hostdev-pf1vf10-test-worker2
  template:
    metadata:
      labels:
        app: sriov-hostdev-pf1vf10-test-worker2
      annotations:
        k8s.v1.cni.cncf.io/networks: hostdev-pf1vf10-worker2
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: sriov-test-worker
      nodeSelector:
        feature.node.kubernetes.io/dpu-enabled: "true"
        kubernetes.io/hostname: "r7525-a"
      containers:
      - name: nginx
        securityContext:
          privileged: true
          capabilities:
            add:
            - NET_ADMIN
        image: nicolaka/netshoot
        command: ["nc", "-kl", "5000"]
        ports:
        - containerPort: 5000
          name: tcp-server
        resources:
          requests:
            cpu: 16
            memory: 6Gi
          limits:
            cpu: 16
            memory: 6Gi
````
</details>


Apply the above yaml files to create test pods.

````
kubectl apply -f manifests/05-test-traffic
````

That will deploy 2 test pods.

Use iperf to test networking between two pods.

![image](https://github.com/user-attachments/assets/942af4de-9857-45e0-b01f-b7cb82603faf)

In this test case 180 Gbits/sec was achieved on pcie4 without any tuning on pods and HW side.


