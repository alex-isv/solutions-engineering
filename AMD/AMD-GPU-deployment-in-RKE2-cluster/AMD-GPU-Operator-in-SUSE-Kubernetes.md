# Deploying AMD GPU-Operator in SUSE RKE3 cluster

## Purpose 
These steps outlines installation of AMD GPU-Operator in SUSE RKE2 Kubernetes cluster and managed by a Rancher server.
AMD GPU-operator can help deploy GPUs in the Kubernetes cluster at scale.

## Prerequisites

SLES based RKE2 cluster managed by a Rancher server. Review [RKE2 installation steps](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment).

 Test case:
 SLES based (15 sp6)
 
 3 (control-plane, etcd) nodes
 
 1 (worker) node with AMD GPU MI210.

 ![image](https://github.com/user-attachments/assets/3b859427-04ec-4500-aecf-9a279591e467)


Please review [AMD GPU-Operator deployment](https://dcgpu.docs.amd.com/projects/gpu-operator/en/latest/installation/kubernetes-helm.html#kubernetes-helm).

**Intall AMD Rocm on the worker node**

That can be done either with a locally installed Rocm driver on the worker node or with the help of the AMD gpu-operator and pre-compiled container based drivers on the registry (work in progress).

Option 1.
Locally installed driver.

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




## Install AMD GPU-operator with helm command.

Follow [Kubernetes (Helm) installation steps](https://dcgpu.docs.amd.com/projects/gpu-operator/en/latest/installation/kubernetes-helm.html).


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

Install CRD:

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

Check output of <ins> amd-smi </ins>

either from the Rancher:

![image](https://github.com/user-attachments/assets/c9418425-0059-44cf-b618-7628e25045a2)

or from the admin node:

![image](https://github.com/user-attachments/assets/8140f76e-2535-415f-be54-296836a08522)




<ins> WORK IN PROGRESS .... </INS>


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
    image: docker.io/username/repo
    # (Optional) Specify the credential for your private registry if it requires credential to get pull/push access
    # you can create the docker-registry type secret by running command like:
    # kubectl create secret docker-registry mysecret -n kmm-namespace --docker-username=xxx --docker-password=xxx
    # Make sure you created the secret within the namespace that KMM operator is running
    imageRegistrySecret:
      name: mysecret
    # Specify the driver version by using ROCm version
    version: "6.2.1"

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

SLES based container should be used for compiling the drivers as described in [Preparing Pre-compiled Driver Images](https://dcgpu.docs.amd.com/projects/gpu-operator/en/latest/drivers/precompiled-driver.html).
That should be pushed to the registry and defined in the DeviceConfig CRD.


Work in progress..









