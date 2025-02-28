# Deploying Nvidia DPU-operator in Suse/Rancher cluster.

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

Don't add worker nodes with BF-3 cards installed to the cluster at the beginning.


