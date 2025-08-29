# Deploying AMD GPU-Operator in SUSE RKE2 cluster

> [!NOTE]
> *Validation steps.*
> 
## Purpose 
These steps outlines installation of AMD GPU-Operator in SUSE RKE2 Kubernetes cluster and managed by a Rancher server.
AMD GPU-operator can help deploy GPUs in the Kubernetes cluster at scale.

## Prerequisites

SLES based RKE2 cluster managed by a Rancher server. Review [RKE2 installation steps](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment).

Test case:

 SLES15 sp6 RKE2 cluster with Rancher server v2.10.2
 
 K3s version v1.31.5+k3s1
  
 RKE2 v1.31

 
 3 (control-plane, etcd) nodes
 
 1 (worker) node with AMD GPU MI210.

 ![image](https://github.com/user-attachments/assets/3b859427-04ec-4500-aecf-9a279591e467)


Please review [AMD GPU-Operator deployment](https://instinct.docs.amd.com/projects/gpu-operator/en/latest/).

**Intall AMD Rocm on the worker node if needed**

> [!NOTE]
> *ROCM is included in SLES kernel, so no needs to install it separately from AMD upstream, unless some additional tools or libraries are needed* AMD gpu-operator should work out of the box with SLES 15. The only path which should be followed is setting the driver to false in the configuration:
> ````
> spec:
>  driver:
>   # disable the installation of our-of-tree amdgpu kernel module
>    enable: false
>  ````
> as listed in [Inbox or Pre-Installed AMD GPU Drivers](https://instinct.docs.amd.com/projects/gpu-operator/en/latest/installation/kubernetes-helm.html#inbox-or-pre-installed-amd-gpu-drivers)
> 

If ROCM needs to be installed locally on the worker node from AMD upstream repo or with the help of the AMD gpu-operator and pre-compiled container based drivers on the registry, follow the below steps.

**Option 1.**
Locally installed driver from AMD upstream repo.

Please review [Rocm installation doc for SLES15](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/install-methods/package-manager/package-manager-sles.html).

````
sudo tee /etc/zypp/repos.d/amdgpu.repo <<EOF
[amdgpu]
name=amdgpu
baseurl=https://repo.radeon.com/amdgpu/6.3.2/sle/15.6/main/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
EOF
````

````
sudo zypper refresh
````

````
sudo tee --append /etc/zypp/repos.d/rocm.repo <<EOF
[ROCm-6.3.2]
name=ROCm6.3.2
baseurl=https://repo.radeon.com/rocm/zyp/6.3.2/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
EOF
````

````
sudo zypper refresh
````

````
sudo zypper --gpg-auto-import-keys install amdgpu-dkms
````

````
sudo zypper --gpg-auto-import-keys install rocm
````

reboot

Follow [post-installation steps](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/install/post-install.html#post-installation-instructions).

Verify installed driver:


![image](https://github.com/user-attachments/assets/0edd326a-abce-4a39-8001-a15250726f63)




**Install AMD GPU-operator with helm command.**

Follow [Kubernetes (Helm) installation steps](https://instinct.docs.amd.com/projects/gpu-operator/en/latest/installation/kubernetes-helm.html).


````
helm repo add rocm https://rocm.github.io/gpu-operator
````
````
helm repo update
````

````
helm install amd-gpu-operator rocm/gpu-operator-charts \
  --namespace kube-amd-gpu \
  --create-namespace \
  --version=v1.1.0
````

Verify installation with

````
kubectl get pods -n kube-amd-gpu
````

**Install CRD:**

1) If the driver was installed locally on the worker node use the following yaml file with <ins> spec.driver.enable=false </ins> option:

````
apiVersion: amd.com/v1alpha1
kind: DeviceConfig
metadata:
  name: test-deviceconfig
  # use the namespace where AMD GPU Operator is running
  namespace: kube-amd-gpu
spec:
  driver:
    # disable the installation of our-of-tree amdgpu kernel module
    enable: false

  devicePlugin:
    devicePluginImage: rocm/k8s-device-plugin:latest
    nodeLabellerImage: rocm/k8s-device-plugin:labeller-latest
        
  # Specify the metrics exporter config
  metricsExporter:
     enable: true
     serviceType: "NodePort"
     # Node port for metrics exporter service, metrics endpoint $node-ip:$nodePort
     nodePort: 32500
     image: docker.io/rocm/device-metrics-exporter:v1.1.0

  # Specifythe node to be managed by this DeviceConfig Custom Resource
  selector:
    feature.node.kubernetes.io/amd-gpu: "true"
````

Import a yaml from the Rancher manager to the <ins> kube-amd-gpu </ins> namespace 


![image](https://github.com/user-attachments/assets/9b10dacb-5e7f-4c1f-82fd-74d9f8584fe6)


or use 

````
kubectl apply -f deviceconfigs.yaml
````

Verify installation either from the Rancher pods section:

![image](https://github.com/user-attachments/assets/21e9e59a-8e48-4367-b305-307e18d28ac9)



or with the following from the admin node:

````
kubectl get deviceconfigs -n kube-amd-gpu -o yaml
````

````
kubectl get nodes -o yaml | grep "amd.com/gpu"
````

![image](https://github.com/user-attachments/assets/0818d9cc-ef65-4c46-9bbf-9a35b3d43f92)



## Test GPU workload

Paste yaml from the Rancher or as 

````
kubectl create -f amd-smi.yaml
````

````
apiVersion: v1
kind: Pod
metadata:
 name: amd-smi
spec:
 containers:
 - image: docker.io/rocm/pytorch:latest
   name: amd-smi
   command: ["/bin/bash"]
   args: ["-c","amd-smi version && amd-smi monitor -ptum"]
   resources:
    limits:
      amd.com/gpu: 1
    requests:
      amd.com/gpu: 1
 restartPolicy: Never
````

Check output of <ins> amd-smi </ins> either from the Rancher:


![image](https://github.com/user-attachments/assets/c9418425-0059-44cf-b618-7628e25045a2)

or from the admin node:

![image](https://github.com/user-attachments/assets/8140f76e-2535-415f-be54-296836a08522)
.
> [!NOTE]
> *Latest validation on rocm-operator 1.2.0 and driver 6.4.0.*
> 

**Option2**


###   Install out-of-tree AMD GPU Drivers with the Operator. <ins> Can be used for some specific custom configurations. </INS>

> [!NOTE]
> *These steps are not needed if using default SLES 15 OS as it has included ROCM as part of the kernel.
> It can be used when extra tools and libraries are needed from AMD upstream ROCM repo.
> 
> Latest validation on rocm-operator 1.2.0 and driver 6.4.0.*
> 
Review attached Dockerfile.

From your worker file build a rocm driver container and push to your registry.

For example in this test case for SLES15 sp6:

uname -r

6.4.0-150600.23.53-default
````
podman build -t ghcr.io/alex-isv/amdgpu-driver --build-arg KERNEL_FULL_VERSION=$(uname -r) --build-arg DRIVERS_VERSION=6.4.0 .
````
````
podman tag ghcr.io/alex-isv/amdgpu-driver:latest ghcr.io/alex-isv/amdgpu-driver:sles-15sp6-6.4.0-150600.23.53-default-6.4.0
````

````
podman push ghcr.io/alex-isv/amdgpu-driver:sles-15sp6-6.4.0-150600.23.53-default-6.4.0
````

When preparing a deviceconfig.yaml file, the pre-build repo with a driver version should be listed there. In my case: 

<ins> image: ghcr.io/alex-isv/amdgpu-driver </ins>

<ins> version: "6.4.0" </ins>


Clone modified rocm/operator repo.

````
https://github.com/alex-isv/rocm-operator-sles.git

````

> [!NOTE]
> *rocm-operator 1.2.0 and driver 6.4.0 in use for this test.*
> 
> In this case, AMD upstream rocm-operator was modified to recognize SLES as a worker node for custom deployments.
> 
> 

Go to 

<ins> ..rocm-operator-sles/helm-charts-k8s </ins> directory from your admin node and install AMD gpu-operator with:

````
helm upgrade --install amd-gpu-operator-sles . --namespace kube-amd-gpu --create-namespace --version=v1.2.0
````

If using a GPU-operator to install drivers, you need to set <ins> spec.driver.blacklist=true </ins> and use the following CRD:

````
apiVersion: amd.com/v1alpha1
kind: DeviceConfig
metadata:
  name: test-deviceconfig
  # use the namespace where AMD GPU Operator is running
  namespace: kube-amd-gpu
spec:
  driver:
    # enable operator to install out-of-tree amdgpu kernel module
    enable: true
    # blacklist is required for installing out-of-tree amdgpu kernel module
    blacklist: true
    # Specify your repository to host driver image
    # DO NOT include the image tag as AMD GPU Operator will automatically manage the image tag for you
    image: ghcr.io/alex-isv/amdgpu-driver
    # (Optional) Specify the credential for your private registry if it requires credential to get pull/push access
    # you can create the docker-registry type secret by running command like:
    # kubectl create secret docker-registry mysecret -n kmm-namespace --docker-username=xxx --docker-password=xxx
    # Make sure you created the secret within the namespace that KMM operator is running
    # Specify the driver version by using ROCm version
    version: "6.4.0"

  devicePlugin:
    devicePluginImage: rocm/k8s-device-plugin:latest
    nodeLabellerImage: rocm/k8s-device-plugin:labeller-latest
        
  # Specify the metrics exporter config
  metricsExporter:
     enable: true
     serviceType: "NodePort"
     # Node port for metrics exporter service, metrics endpoint $node-ip:$nodePort
     nodePort: 32500
     image: docker.io/rocm/device-metrics-exporter:v1.1.0

  # Specifythe node to be managed by this DeviceConfig Custom Resource
  selector:
    feature.node.kubernetes.io/amd-gpu: "true"
````


Import CRD to install Rocm by the operator:

````
kubectl apply -f test-deviceconfig.yaml
````

Example of deployed operator with deviceconfig:


<img width="1765" height="695" alt="image" src="https://github.com/user-attachments/assets/b128c32a-4ac4-4b65-adde-7e686d982f43" />


<img width="1890" height="734" alt="image" src="https://github.com/user-attachments/assets/fc36cc70-ec9d-4050-8d3e-fceff6e7bf20" />

For Ollama AI workload example see [Installing Open WebUI with AMD + ROCm for Ollama in SUSE/Rancher RKE2 Kubernetes cluster](https://github.com/alex-isv/solutions-engineering/blob/main/AMD/AI/Deploying_open-webui-ollama_in_AMD-based_RKE2-cluster.md#install-open-webui-with-helm).

Latest Ollama tested 7.0.1

<details><summary>Expand for detailed Ollama helm chart values</summary>
 
````yml
---
affinity: {}
annotations: {}
args: []
clusterDomain: cluster.local
command: []
commonEnvVars: []
containerSecurityContext: {}
copyAppData:
  args: []
  command: []
  resources: {}
databaseUrl: ''
enableOpenaiApi: true
extraEnvFrom: []
extraEnvVars:
  - name: OPENAI_API_KEY
    value: 0p3n-w3bu!
extraInitContainers: []
extraResources: []
hostAliases: []
image:
  pullPolicy: IfNotPresent
  repository: ghcr.io/open-webui/open-webui
  tag: ''
imagePullSecrets: []
ingress:
  additionalHosts: []
  annotations: {}
  class: ''
  enabled: true
  existingSecret: ''
  extraLabels: {}
  host: ollama.isv.suse
  tls: false
livenessProbe: {}
logging:
  components:
    audio: ''
    comfyui: ''
    config: ''
    db: ''
    images: ''
    main: ''
    models: ''
    ollama: ''
    openai: ''
    rag: ''
    webhook: ''
  level: ''
managedCertificate:
  domains:
    - chat.example.com
  enabled: false
  name: mydomain-chat-cert
nameOverride: ''
namespaceOverride: ''
nodeSelector: {}
ollama:
  enabled: true
  fullnameOverride: open-webui-ollama
  ollama:
    gpu:
      enabled: true
      number: 1
      type: amd
  persistentVolume:
    enabled: true
ollamaUrls: []
ollamaUrlsFromExtraEnv: false
openaiBaseApiUrl: open-webui-ollama.ollama.svc.cluster.local
openaiBaseApiUrls: []
persistence:
  accessModes:
    - ReadWriteOnce
  annotations: {}
  azure:
    container: ''
    endpointUrl: ''
    key: ''
    keyExistingSecret: ''
    keyExistingSecretKey: ''
  enabled: true
  existingClaim: ''
  gcs:
    appCredentialsJson: ''
    appCredentialsJsonExistingSecret: ''
    appCredentialsJsonExistingSecretKey: ''
    bucket: ''
  provider: local
  s3:
    accessKey: ''
    accessKeyExistingAccessKey: ''
    accessKeyExistingSecret: ''
    bucket: ''
    endpointUrl: ''
    keyPrefix: ''
    region: ''
    secretKey: ''
    secretKeyExistingSecret: ''
    secretKeyExistingSecretKey: ''
  selector: {}
  size: 2Gi
  storageClass: local-path
  subPath: ''
pipelines:
  enabled: true
  extraEnvVars: []
podAnnotations: {}
podLabels: {}
podSecurityContext: {}
priorityClassName: ''
readinessProbe: {}
replicaCount: 1
resources: {}
revisionHistoryLimit: 10
runtimeClassName: ''
service:
  annotations: {}
  containerPort: 8080
  labels: {}
  loadBalancerClass: ''
  nodePort: ''
  port: 80
  type: ClusterIP
serviceAccount:
  annotations: {}
  automountServiceAccountToken: false
  enable: true
  name: ''
sso:
  enableGroupManagement: false
  enableRoleManagement: false
  enableSignup: false
  enabled: false
  github:
    clientExistingSecret: ''
    clientExistingSecretKey: ''
    clientId: ''
    clientSecret: ''
    enabled: false
  google:
    clientExistingSecret: ''
    clientExistingSecretKey: ''
    clientId: ''
    clientSecret: ''
    enabled: false
  groupManagement:
    groupsClaim: groups
  mergeAccountsByEmail: false
  microsoft:
    clientExistingSecret: ''
    clientExistingSecretKey: ''
    clientId: ''
    clientSecret: ''
    enabled: false
    tenantId: ''
  oidc:
    clientExistingSecret: ''
    clientExistingSecretKey: ''
    clientId: ''
    clientSecret: ''
    enabled: false
    providerName: SSO
    providerUrl: ''
    scopes: openid email profile
  roleManagement:
    adminRoles: ''
    allowedRoles: ''
    rolesClaim: roles
  trustedHeader:
    emailHeader: ''
    enabled: false
    nameHeader: ''
startupProbe: {}
strategy: {}
tika:
  enabled: false
tolerations: []
topologySpreadConstraints: []
volumeMounts:
  container: []
  initContainer: []
volumes: []
websocket:
  enabled: false
  manager: redis
  nodeSelector: {}
  redis:
    affinity: {}
    annotations: {}
    args: []
    command: []
    enabled: true
    image:
      pullPolicy: IfNotPresent
      repository: redis
      tag: 7.4.2-alpine3.21
    labels: {}
    name: open-webui-redis
    pods:
      annotations: {}
      labels: {}
    resources: {}
    securityContext: {}
    service:
      annotations: {}
      containerPort: 6379
      labels: {}
      nodePort: ''
      port: 6379
      type: ClusterIP
    tolerations: []
  url: redis://open-webui-redis:6379/0
````

</details>

<img width="1790" height="417" alt="image" src="https://github.com/user-attachments/assets/b0ecc09d-ee4d-406a-9bce-856e3cf68def" />

For the operator monitoring setup review [Prometheus Integration with Metrics Exporter](https://instinct.docs.amd.com/projects/gpu-operator/en/latest/metrics/prometheus.html#)

Rancher Monitoring already has an integrated Prometheus and Grafana Dashboards.




