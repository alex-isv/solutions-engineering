# Running Ollama on RKE2 with ARM based worker node.

## Prerequisites

<ins> Setup environment </ins>


- Harvester 1.3.1 running on GIGABYTE Ampere Altra ARMv8 80 cores.
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

![image](https://github.com/user-attachments/assets/0ca5254f-fcb5-447d-bb47-e8eda9c16ab3)

Edit open-webui StatefulSets:
![image](https://github.com/user-attachments/assets/32262025-b471-469d-86ca-dc0c33034b67)

and add WEBUI_AUTH with FALSE value to access without authentication.

![image](https://github.com/user-attachments/assets/be8dfad3-125e-4fe2-9bcd-bbffa7354039)

Verify nginx url from Ingresses:

![image](https://github.com/user-attachments/assets/06e2e666-303a-4686-9b6d-b18966d3dbbe)

and check assigned IP with:
````
kubectl -n openwebui get ing
````

![image](https://github.com/user-attachments/assets/35f9bd3b-971b-4c3a-bb68-4f52595d6ccc)

In my case I have 2 nodes with Worker roles available on the cluster.

Add listed IP to your local machine /etc/hosts:

<ins> 192.168.150.115 ollama.isv.suse ollama </ins>


## Access Open WebUI from your browser and test Ollama
