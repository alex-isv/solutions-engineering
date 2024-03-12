# Nvidia DGX on SUSE-Rancher RKE2 cluster validation setup steps


Test environment:
SUSE Harvester physical node with 4 VM:
1 Rancher server VM
3 VMs as RKE2 cluster (all VMs are SLE Micro based).
2 Nvidia DGX servers physical nodes 
Setup:
Due to limited resources for this particular verification test, SUSE Harvester server was used to mimic a test kubernetes environment.
Harvester is a cloud-native hyperconverged infrastructure solution for Kubernetes which designed to simplify VMs workloads with integrated storage capabilities and supports containerized environments automatically through integration with Rancher. Please review -> https://docs.harvesterhci.io/v1.1 for more details.

![harv-1](https://github.com/alex-isv/solutions-engineering/assets/52678960/c4c4d0ce-09b4-43da-815f-d360271c6b88)

For the cluster nodes SLE Micro 5.4 was used as a base OS for a Rancher server manager and RKE2 cluster nodes.
Sle Micro is designed as a host OS to run containers. It’s a minimal/stripped OS with a transactional-update.
For more details on Micro, review our SLE Micro deployment guide > https://documentation.suse.com/sle-micro/5.4/pdf/book-deployment-slemicro_en.pdf
And the admin guide >  https://documentation.suse.com/sle-micro/5.4/pdf/book-administration-slemicro_en.pdf
Install Rancher server on test1 VM.
> https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli
Steps:
Install helm.
If PackageHub repo is not activated, enable it with 
SUSEConnect -p PackageHub/15.4/x86_64
And install helm:
# transactional-update pkg install helm-3.8.0-bp154.2.27

Install K3s on Linux
# curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.24.14+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -


# k3s kubectl get nodes

# kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml
# helm repo add jetstack https://charts.jetstack.io
# helm repo update
# export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.11.0
# kubectl get pods --namespace cert-manager

# helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
# export HOSTNAME="test1.eth.cluster"
# export RANCHER_VERSION="2.7.3"

# kubectl create namespace cattle-system
# helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=test1.eth.cluster --set version=2.7.4 --set replicas=1
Go to Rancher server URL and login > 


Run the command from <For a Helm installation> to show generated password to enter and create a new one.
Integrate Rancher with Harvester as described in > https://docs.harvesterhci.io/v1.1/rancher/rancher-integration#virtualization-management





Create an RKE2 cluster.
From Rancher server go to the Cluster Management and select RKE2 and click Custom

Select a proper/certified Kubernetes version and a cloud provider




In this test setup we used RKE2 embedded
Click <Create> and select Node Role and copy registration command




Paste to the target node.

It’s also possible to create RKE2 cluster directly in one step from the Harvester with a node driver as described in > https://docs.harvesterhci.io/v1.1/rancher/node/node-driver#rke2-kubernetes-cluster
Where you can define a machine pool and a machine count preconfigured with a proper cloud provider.
From Machines tab of the rke2-cluster verify that node was deployed.

Make sure that you have the odd number of nodes in RKE2 cluster. In this case 3 nodes total with all 3 roles assigned.



Add DGX nodes to the existing RKE2 cluster:

Go to the Registration tab, select worker role and paste to DGX nodes.

 Verify that all nodes deployed to the cluster.




Install and test Nvidia gpu-operator on the cluster.
From Rancher app, add Nvidia gpu-operator helm chart and modify config. with the following


Select Customize Helm and add the following options:

https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/gpu-operator-mig.html
 mig.strategy should be set to mixed when MIG mode is not enabled on all GPUs on a node.
In the yaml, if driver already installed change value to false


Under toolkit add the following values:


Note, that by default migManager is coming as all-disabled


Once installed, verify logs
Logs can be verified from Workloads>Pods



Verify if test functionality of nvidia-operator-validator pod are passed.




When enabling MIG change node’s label to a correct value for nvidia.com/mig.config
When enabling MIG change node’s label to a correct value for nvidia.com/mig.config

Default value is ‘all-disabled’
Check correct profile for your GPU type. Note: A100-40Gb and A100-80Gb have diff. Profile.
Check right profile from > Storage > ConfigMaps > default-mig-parted-config
For ex. 


In this example all-1g.10gb profile can be used for A100-1g.10gb
Go to Cluser > Nodes > select your proper node to enable mig, > click config > Labels & Annotation

> find nvidia.com/mig.config label and verify your current profile. 
To change, click on the 3 dots on the right and select ‘Edit Config’

Click Labels and change mig.config to your desired profile and click ‘Save’

Verify that the state is showing Success.

From ‘pending’ it should change to ‘success’
You can check Mig-manager logs



Upon successful change you should be able to see changes in labels on the node


You can verify from DGX node



You can also use kubectl to add a label to the kubernetes node >
kubectl label nodes basepod-dgx04 nvidia.com/mig.config=all-1g.10gb
In order to enable mig on a dedicated GPU you need to add a custom entry in the configmap.
Storage > ConfigMaps > default-mig-parted-config
https://github.com/NVIDIA/mig-parted/blob/main/examples/dgx-station-80gb-config.yaml

And change a node’s label to custom-config profile

Verify from DGX node > 


Install Longhorn on the Rancher.
Before installing a Longhorn make sure that each node on the cluster has open-iscsi installed.
Also, Ubuntu DGX nodes had mask by default for iscsi, so need to run > # sudo systemctl unmask iscsid.service to unmask it.




Using Opni to bring a workload to GPU.
Opni designed for multi-cluster and multi-tenant observability on Kubernetes.
Opni installation:
Review doc > https://opni.io/installation/opni/
Install cert manager as a prereq.
Navigate to Apps -> Repositories in the Rancher UI. Name the repository and select the 'Git repository containing Helm chart or cluster template definitions' option.
Enter the following git url:
https://github.com/rancher/opni.git


And the following branch:
charts-repo

Select Opni helm chart


Click Install
Select New Namespace (call it opni)

Use a localhost for the GW hostname

Select a LoadBalancer as a service type. Click Next and Install.


Enable Opni loggin > https://opni.io/installation/opni/backends
You need to port forward from your local machine to access a dashboard.
> kubectl -n opni port-forward svc/opni-admin-dashboard web:web

To access the cluster from the local machine you need to install kubectl and copy the cluster's kubeconfig file (rke2.yaml) to your local ~/.kube/config directory and > export KUBECONFIG=/root/.kube/config/rke2.yaml
 

Access dashboard from the browser > http://localhost:12080
Note: use Chrome


Click on the Loggin tab from the left and install

Review storage provisioning from Rancher Storage > PersistentVolumeClaims 

From Longhorn UI, you can review available nodes on the cluster and the storage >



Enable Loggin from the Opni dashboard:



Select 3 replicas for the Controlplane Pods

We used a persistent storage with 3 replicas for the longhorn storage class.

Opni-controlplane-0, 1 and 2 are attached to 3 diff. nodes from the Longhorn.


Login to OpenSearch dashboard
kubectl -n opni port-forward svc/opni-opensearch-svc-dashboards 5601:5601



Get a username: kubectl get secret -n opni opni-admin-password -o jsonpath='{.data.username}' | base64 –d
And a passwd: kubectl get secret -n opni opni-admin-password -o jsonpath='{.data.password}' | base64 –d
Enable Opni AIOps
Enable Log Anomaly from Opni Dashboard > https://opni.io/installation/opni/aiops

In our case Deployment Watchlist:
Auto generated models for user selected workloads
User selects 1 or more workload deployments important to them
Opni will self train a model and provide insights for logs belonging to user selected workloads
NVIDIA GPU is required to run



Once enabled > opni-svc-gpu-controller pod will be deployed.
From AIOps click on Deployment Watchlist (wait for some time to collect logs)
Select a watchlist from the dashboard.


Depends on the size, it may take a few hours to collect logs

Opni-svc-gpu-controller is taking care of a workload to GPU node.



In this case dgx03 is used as the only node with GPU (setting in yaml)

We cordoned another node with GPU to use a specific GPU node.

For more heavier workload I used a kubernetes-manifests
from https://github.com/GoogleCloudPlatform/microservices-demo
OPNI will use that workload to redirect to nodes where GPUs are located and will utilize a gpu workload.
opni-svc-gpu-controller pod is the one used to redirect the workload to GPUs.
Import kubernetes-manifest.yaml file from Rancher

That will bring some workload to the cluster >



From Opni dashboard Deployment Watchlist, select ‘default’ namespace


With generated logs from kubernetes-manifests deployment.
From OpenSearch dashboard you can select logs and the workload utilization






From opni namespace check opni-svc-gpu-controller deployment it should be 100% and deployed once all logs collected.

For a dedicated workload to a specific mig partition a nodeSelector can be added to the test yaml file as nodeSelector: nvidia.com/mig-1g.10gb: 1
** Note: currently opni is hard coded to be used with a gpu without a MIG so any other gpu tests can be used if allowed.
Monitoring.
Opni has an integrated monitoring service. https://opni.io/installation/opni/backends
You can enable opni monitoring from the dashboard.


In this particular setup due to isolated lab environment, Grafana won’t be able to access it for opni, since it requires the oauth flow. Opni was developed to use openid login for Grafana. In a production environment it’s usually using some authentication like auth0 or aws congnito.

The 2nd option is to use the integrated Rancher monitoring tool.
Go to the Cluster Tools and install Rancher Monitoring.

Edit yaml file and add the following values for Prometheus:
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

Install and verify that it’s running.
The default Admin username and password for the Grafana instance is admin/prom-operator



Import Nvidia dashboard 
> https://grafana.com/docs/grafana/latest/dashboards/manage-dashboards/


Note: In this particular lab setup, due to network configuration and isolation, Prometheus won’t be able to access it from the remote machine’s browser.

In non-restricted lab environment with Grafana Nvidia DCGM Exporter dashboard
with some tensorflow workload, It should look similar to this >


=============================

To uninstall Nvidia GPU drivers >>
Run the following commands to uninstall CUDA: 
zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"

rm -rf /usr/local/cuda-11.4 
Run the following command to uninstall the GPU driver: 
               zypper remove "*nvidia*" 
reboot
============================================================================

