# Installing Open WebUI with AMD + ROCm for Ollama in SUSE/Rancher RKE2 Kubernetes cluster

## Purpose 
These steps outlines installation of Open WebUI + Ollama using AMD GPU in SUSE RKE2 Kubernetes cluster and managed by a Rancher server.

## Prerequisites

<ins> Setup environment </ins>

![image](https://github.com/user-attachments/assets/78a31357-c061-47f3-a040-931567c9235b)


- SL Micro 6.0 based RKE2 cluster with a Rancher manager. Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster.

 ![image](https://github.com/user-attachments/assets/b8a88b33-b307-47ef-baf1-f447b3efdb8c)


In the above example, the RKE2 5 nodes cluster is shown from the Rancher console.

- MI210 AMD GPU installed in the worker node.

  

Install [ROCm and AMD GPU device plugin](https://github.com/alex-isv/solutions-engineering/blob/main/AMD/AMD-GPU-deployment-in-RKE2-cluster/Deploying-AMD-GPU-in-SUSE-Kubernetes-stack.md#install-rocm-on-the-worker-gpu-node).

For more details review [AMD GPU device plugin for Kubernetes](https://github.com/ROCm/k8s-device-plugin#amd-gpu-device-plugin-for-kubernetes).

For the larger cluster use [AMD GPU Operator](https://github.com/ROCm/gpu-operator).

If planning to use a local storage, install a Local Path Provisioner as described [here](https://github.com/rancher/local-path-provisioner)

````
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.29/deploy/local-path-storage.yaml
````
````
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
````


## Install Open WebUI with Helm

Add a new repository from Rancher Repositories and call it openwebui with url: https://helm.openwebui.com/ 

![image](https://github.com/user-attachments/assets/b8f415a9-9658-4d8e-a76d-ed4fbca2d7e8)

Click Web-UI helm chart.

![image](https://github.com/user-attachments/assets/f78fabb8-293a-49c6-a2b3-e71d4b82764c)

Create a new namespace called ollama.
Customize Helm with the following values:

````
affinity: {}
annotations: {}
clusterDomain: cluster.local
containerSecurityContext: {}
extraEnvVars:
  - name: OPENAI_API_KEY
    value: 0p3n-w3bu!
image:
  pullPolicy: IfNotPresent
  repository: ghcr.io/open-webui/open-webui
  tag: latest
imagePullSecrets: []
ingress:
  annotations: {}
  class: nginx
  enabled: true
  existingSecret: ''
  host: ollama.isv.suse
  tls: false
nameOverride: ''
nodeSelector: {}
ollama:
  enabled: true
  fullnameOverride: open-webui-ollama
  ollama:
    gpu:
      enabled: true
      number: 1
      type: amd
    models:
      - llama3
  persistentVolume:
    enabled: true
ollamaUrls: []
openaiBaseApiUrl: open-webui-ollama.ollama.svc.cluster.local
persistence:
  accessModes:
    - ReadWriteOnce
  annotations: {}
  enabled: true
  existingClaim: ''
  selector: {}
  size: 2Gi
  storageClass: local-path
pipelines:
  enabled: true
  extraEnvVars: []
podAnnotations: {}
podSecurityContext: {}
replicaCount: 1
resources: {}
service:
  annotations: {}
  containerPort: 8080
  labels: {}
  loadBalancerClass: ''
  nodePort: ''
  port: 80
  type: ClusterIP
tolerations: []
topologySpreadConstraints: []
````
Modify according to your setup. For the storageClass, longhorn can be used as well for which a new StorageClass should be created in advanced and set to default.


Check deployed pods from Workloads:

![image](https://github.com/user-attachments/assets/0ca5254f-fcb5-447d-bb47-e8eda9c16ab3)

Edit open-webui StatefulSets:
![image](https://github.com/user-attachments/assets/32262025-b471-469d-86ca-dc0c33034b67)

and add WEBUI_AUTH with FALSE value to access without authentication.

![image](https://github.com/user-attachments/assets/be8dfad3-125e-4fe2-9bcd-bbffa7354039)

Verify nginx url from Ingresses:

![image](https://github.com/user-attachments/assets/06e2e666-303a-4686-9b6d-b18966d3dbbe)

and check assigned IP with:
````
kubectl -n ollama get ing
````

![image](https://github.com/user-attachments/assets/35f9bd3b-971b-4c3a-bb68-4f52595d6ccc)

In my case I have 2 nodes with Worker roles available on the cluster.

Add listed IP to your local machine /etc/hosts:

<ins> 192.168.150.115 ollama.isv.suse ollama </ins>


## Access Open WebUI from your browser and test Ollama

![image](https://github.com/user-attachments/assets/b3a77225-a2fb-4630-b76e-5ccfe4118e77)

## Using AMD CPUs with Ollama

Ollama can also be run on modern CPUs if GPU is not available.

In the below test example a worker node with 2 AMD EPYC 7763 64-Core processors with 64 phicisal cores each were used with llama3.1 model. (256 total threads)

>[!NOTE]
> In order to use just CPUs, you need to remove or disable a GPU in the mentioned Helm chart.

 In the below CPU utilization example llama3 model was used on just CPUs

![image](https://github.com/user-attachments/assets/00ab7508-1d7b-4c3b-993f-83001f1e01a3)

![image](https://github.com/user-attachments/assets/601ca7bc-0a3d-442a-bf5b-b15974269eea)







