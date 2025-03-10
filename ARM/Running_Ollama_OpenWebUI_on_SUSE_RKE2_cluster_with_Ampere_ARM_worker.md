# Running Ollama on RKE2 with ARM based worker node.

## Prerequisites

<ins> Setup environment </ins>


- Harvester 1.3.1 hypervisor running on GIGABYTE Ampere Altra ARMv8 80 cores. (For the production environment it's recommended to have a cluster with at least 3 Harvester nodes)
  - Micro 6.0 ARM based VMs as part of the RKE2 cluster.
- 2nd GIGABYTE Ampere Altra as a worker node (SLES 15.6 ARM based).

![image](https://github.com/user-attachments/assets/bb3253d5-59ab-4584-af31-37ecb4eea1d9)

- SL Micro 6.0 based RKE2 cluster with a Rancher manager. Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster.

  
![image](https://github.com/user-attachments/assets/529117ac-81ab-4412-9fe3-f106a7d1f83a)

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

Create a new namespace called openwebui.
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
  host: openwebui.isv.suse
  tls: false
nameOverride: ''
nodeSelector: {}
ollama:
  enabled: true
  fullnameOverride: open-webui-ollama
  ollama:
    models:
      - llama3
      - llama3.1
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

![image](https://github.com/user-attachments/assets/8762ae26-5589-4533-878c-2980abba71c3)


Edit open-webui StatefulSets:

![image](https://github.com/user-attachments/assets/32262025-b471-469d-86ca-dc0c33034b67)

and add WEBUI_AUTH with FALSE value to access without authentication.

![image](https://github.com/user-attachments/assets/be8dfad3-125e-4fe2-9bcd-bbffa7354039)

Verify nginx url from Ingresses:

![image](https://github.com/user-attachments/assets/783d8f35-6b01-42f2-aaf8-871df87ad21e)


Add your worker's IP to your local machine /etc/hosts:

<ins> 192.168.150.92 openwebui.isv.suse ollama </ins>


## Access Open WebUI from your browser and test Ollama

![image](https://github.com/user-attachments/assets/5c457637-a927-4737-9915-35942cc6383e)

In the above example, llama3 model was used with 64 threads defined.

![image](https://github.com/user-attachments/assets/48750a68-5adc-49af-b8cd-5e5d333a93f1)

Example of CPU cores utilization.

![image](https://github.com/user-attachments/assets/6f87087f-8fb0-4005-a598-2ba6d1632305)

Example of open-webui-ollama pod workload.

