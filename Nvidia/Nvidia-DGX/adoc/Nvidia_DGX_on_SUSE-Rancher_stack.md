# Using Nvidia DGX with SUSE-Rancher RKE2 cluster
## Purpose:
This document outlines installation and test steps completed by SUSE to certify the successful\
deployment of its Enterprise Container Management (ECM) software stack with the NVIDIA\
DGX as a Kubernetes target node that can be used for the deployment of accelerated\
workloads leveraging NVIDIA GPUs.



Test environment:

SUSE Harvester physical node with 4 VM:\
1 Rancher server VM\
3 VMs as RKE2 cluster (all VMs are SLE Micro based).\
2 Nvidia DGX servers physical nodes

Setup:\
Physical servers or virtualized environment can be used. For simplicity, SUSE Harvester server was used as a test Kubernetes environment.\
Harvester is a cloud-native hyperconverged infrastructure solution for Kubernetes which designed to simplify VMs workloads with integrated storage capabilities and supports containerized environments automatically through integration with Rancher. Please review [Harvester documentation](https://docs.harvesterhci.io/v1.2) for more details.

![harv-1](https://github.com/alex-isv/solutions-engineering/assets/52678960/c4c4d0ce-09b4-43da-815f-d360271c6b88)

For the cluster nodes SLE Micro 5.4 was used as a base OS for a Rancher server manager and RKE2 cluster nodes.

Sle Micro is designed as a host OS to run containers. It’s a minimal/stripped OS with a transactional-update.
For more details on Micro, review [SLE Micro deployment guide](https://documentation.suse.com/sle-micro/5.4/pdf/book-deployment-slemicro_en.pdf)
and the [SLE Micro Admin guide](https://documentation.suse.com/sle-micro/5.4/pdf/book-administration-slemicro_en.pdf)

**Install a Rancher server on test1 VM.**

For the reference use [Rancher documentation](https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli)

> [!NOTE]
> Verify SUSE components support matrix before the installation (https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/rancher-v2-8-2/)

Steps:

If PackageHub repo is not activated, enable it with
````
SUSEConnect -p PackageHub/15.5/x86_64
````

Install helm:
````
transactional-update pkg install helm-3.8.0-bp154.2.27
````

Install K3s on Linux:
````
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.10+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
````
Source the environment
````
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml \
````
Install a cert-manager:
````
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml \
helm repo add jetstack https://charts.jetstack.io \
helm repo update
````

````
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
````

Install a Rancher server:
````
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable \
kubectl create namespace cattle-system \
helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=test1.eth.cluster --set version=2.8.2 --set replicas=1
````

Go to Rancher server URL login and change the password.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/81447757-9d1d-4360-8dd3-c648cf7c75ba)

It's possible to integrate Rancher with Harvester as described in (https://docs.harvesterhci.io/v1.2/rancher/index)


**Create an RKE2 cluster**

From Rancher server go to the Cluster Management and select RKE2 and click Custom

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/847f1dcc-ac01-4286-8332-05c29cf6e250)

Select a proper/certified Kubernetes version and a cloud provider

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d5be1b49-e000-4594-92ee-5ede9869866b)



In this test setup we used RKE2 embedded

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/7965ff0a-bf61-49fe-9030-3e1623ec1c4c)

Click <Create> and select a proper Node Role and copy registration command

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3ccdf799-e97c-4214-a1d0-739057b96873)


Paste a registration command to the target nodes.

> [!TIP]
> It’s also possible to create RKE2 cluster directly in one step from the Harvester with a node driver as described in (https://docs.harvesterhci.io/v1.2/rancher/node/rke2-cluster)
> Where you can define a machine pool and a machine count preconfigured with a proper cloud provider.

From Machines tab of the rke2-cluster verify that node was deployed and part of the RKE2 cluster:
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/aed61a7c-a76c-4df8-88e8-844aebf30e1a)


Make sure that you have the odd number of nodes in RKE2 cluster. In this test case 3 nodes total with all 3 roles assigned:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/349407e6-6ba7-4489-aebc-9c654755217a)




<ins>Add DGX nodes to the existing RKE2 cluster</ins>

Go to the Registration tab, select worker role, copy and paste a registration command to DGX nodes.

 Verify that all nodes deployed to the cluster.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/0b646e87-cb5a-4b6d-8c5e-7843b446c3b3)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/2d7d9918-4716-4e4a-b4d3-43f4e61c73a7)

> [!TIP]
> To access the cluster from the local machine you need to install kubectl and copy the cluster's kubeconfig file (rke2.yaml) to your local `~/.kube/config` directory and run `export KUBECONFIG=/root/.kube/config/rke2.yaml`

## **Install and test Nvidia gpu-operator on the cluster**

From Rancher add a GPU-OPERATOR repo.\
Add Nvidia GPU-OPERATOR helm chart and modify config. with the following parameters:


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/4fda539c-e556-4668-9309-793f39345195)


Select Customize Helm and add the following options:


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c63f2044-9885-4c5a-8167-0b896c7f1f00)


In the yaml, if driver already installed change value to false

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/52f23d2c-dcc2-4308-bb5c-47d8e05749f9)


Under toolkit add the following values:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/25014bd9-11db-493c-bf66-4b6fbae2c1e4)


> [!NOTE]
> By default migManager is coming as *all-disabled*

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/7668ec1d-f8be-4796-b396-82561285d1f6)


Once installed, verify logs
Logs can be verified from Workloads>Pods

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e8158d5f-2c08-442d-b06f-602fc6c1fbaa)


Verify if test functionality of nvidia-operator-validator pod is passed.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/55a1b064-c1a6-46c1-9c97-ca1ca58d7245)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/a0713d24-6207-467b-b508-cd55fe280aa6)

You can also install a GPU-Operator with [helm commands](https://github.com/alex-isv/solutions-engineering/blob/main/Nvidia/Nvidia_GPU-Operator_in_SUSE-Rancher_stack/Installing_Nvidia_GPU-Operator_in_SLE_based_RKE2_cluster.md#install-a-gpu-operator-with-helm-command)


When enabling MIG change node’s label to a correct value for nvidia.com/mig.config

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/aecc59ff-6630-4440-ba70-46f79e75c355)


For the reference review (https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html)

 *mig.strategy* should be set to mixed when MIG mode if not enabled on all GPUs on a node.

Default value is *all-disabled*

Check a correct profile for your GPU type.
> [!NOTE]
>  A100-40Gb and A100-80Gb have diff. profile.
> Check a correct profile from > Storage > ConfigMaps > default-mig-parted-config

For example: 

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/dee6d55a-d38d-4a60-92fb-7326a6839d86)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/b29ab028-6c8c-43c6-9e9a-8621424143ed)


In this example all-1g.10gb profile can be used for A100-1g.10gb

Go to Cluser > Nodes > select your proper node to enable mig, > click config > Labels & Annotation

 find nvidia.com/mig.config label and verify your current profile. 
 
To change, click on the 3 dots on the right and select ‘Edit Config’

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/fb2f1176-b905-41c5-aac4-643bdf258fd4)


Click Labels and change mig.config to your desired profile and click ‘Save’


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d7c31ee1-e256-4162-9be1-4f4700ae63ec)


From ‘pending’ it should change to ‘success’

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c2a8691d-f361-4355-8bd7-5eed2700e84c)



You can check Mig-manager logs

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/94eb448f-efb7-4484-8164-d094b3d9ab32)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/82f0cb56-91c2-4a6d-aa3f-2ccc0fc9d71c)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/6af687aa-19f8-4ebd-81e0-76f2ce3fe0c3)


Upon successful change you should be able to see changes in labels on the node

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/1d85d41e-cc1c-484a-b190-06eb10dac6b4)


You can also verify from DGX node

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/8b0b4fa7-2d82-4be3-9860-dd521450c764)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/73cad02e-afae-4bb0-9717-3a69272da66e)


As an option you can also use kubectl to add a label to the kubernetes node:
````
kubectl label nodes basepod-dgx04 nvidia.com/mig.config=all-1g.10gb
````

In order to enable mig on a dedicated GPU you need to add a custom entry in the configmap.

Storage > ConfigMaps > default-mig-parted-config

As describe in (https://github.com/NVIDIA/mig-parted/blob/main/examples/dgx-station-80gb-config.yaml)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/01cbbce1-fe10-43c4-9857-35a3af79a39d)


and change a node’s label to custom-config profile

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/2654969f-00b2-444c-98e4-e76ca6bd473e)


Verify from DGX node 

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/13db1d09-971e-4489-9d6c-0b450568c1ca)


As an option you can install a Longhorn on the Rancher.

> [!NOTE]
> Before installing a Longhorn make sure that each node on the cluster has open-iscsi installed.\

Also, Ubuntu DGX node has a mask set by default for iscsi, so need to unmask by running:
````
sudo systemctl unmask iscsid.service
````


Review storage provisioning from Rancher Storage > PersistentVolumeClaims 

From Longhorn UI, you can review available nodes on the cluster and the storage 

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/750ecff2-e523-46de-8f81-92e608f3335c)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/39da69ad-b413-4d20-9e7a-9b5660c8765e)



**Bringing a test workload**

 For the reference review (https://developer.nvidia.com/blog/getting-kubernetes-ready-for-the-a100-gpu-with-multi-instance-gpu/) which can be used for different Nvidia tests including MIG strategy.


From your Master node deploy tf-benchmarks.yaml file with
````
kubectl apply -f tf-benchmarks.yaml
````

or from the Rancher Dashboard click *Import Yaml* and paste the following:
````
 # tf-benchmarks.yaml
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

 
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9d4298fd-5398-4d09-80f9-98f5ab1e9b3e)


Click import which will create tf-benchmark pod.\
While pod is in the training mode, run the nvidi-smi command to validate the workload:
````
kubectl exec -it \
"$(for EACH in \
$(kubectl get pods -n gpu-operator \
-l app=nvidia-driver-daemonset \
-o jsonpath={.items..metadata.name}); \
do echo ${EACH}; done)" \
-n gpu-operator \
nvidia-smi
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/157b4233-24d5-462d-8085-b15e9f90c3af)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5616626e-ca0c-4295-8cbd-bf8598869f44)


Also, you can check logs from tf-benchmarks pod 
````
kubectl logs tf-benchmarks
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c9e0d965-ad33-4c02-b609-4a010adb87b9)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/97379bec-fd4a-4809-85b3-428f2161f33b)


Or simply click on pod’s View Logs  >

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/b3e84615-c956-44e5-ac4b-cd2cc44ea3a6)




### <ins>**Review GPU metrics**</ins>

To view GPU metrics modify _Prometheus_ yaml in rancher-monitoring during Rancher-Monitoring installation
````
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    additionalScrapeConfigs:
    - job_name: gpu-metrics
      scrape_interval: 1s
      metrics_path: /metrics
      scheme: http
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - gpu-operator
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_node_name]
        action: replace
        target_label: kubernetes_node
````

In Prometheus panel enter _DCGM_FI_DEV_GPU_TEMP_

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/23831b93-1b8c-45a9-a6dc-716ad778bde0)


Import NVIDIA DCGM Exporter Dashboard from Grafana

Open Grafana >

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/6439741b-d4a0-4ed5-8700-5d7fcca1979b)

Search for NVIDIA DCGM dashboard

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5d98bb90-d052-44ce-8013-9723eb9b6c4f)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/191aae01-53aa-4ade-9333-ff983b57d5c1)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/8aa13232-e073-4e33-9a49-caa4c4b07a22)



Diff. test values will give you diff numbers.
For ex. changing arguments can increase the GPU utilization:
````
python tf_cnn_benchmarks.py --num_gpus=1 --batch_size=1024 --model=resnet50
          --variable_update=parameter_server --use_fp16
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/093af05b-0202-4bea-9a3e-d2a7b4d8b290)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/65687675-62f3-409e-8d6f-2a339562b1e1)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ae2a905b-8faa-492e-a3dc-90e7fb6e2c2e)


Another example:


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9bb8c71b-6b76-4191-9dc0-288f1e5c721e)


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5559c4eb-80b8-4452-9b20-faf3c098b30f)



![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/c04ca0fb-87a9-49dc-bdfc-1e824a2af8e6)


More _tf_cnn_benchmarks_ tests are available at  (https://github.com/tensorflow/benchmarks/tree/master/scripts/tf_cnn_benchmarks)







