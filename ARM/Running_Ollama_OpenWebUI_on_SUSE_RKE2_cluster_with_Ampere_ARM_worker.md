# Running Ollama on RKE2 with ARM based worker node.

## Prerequisites

<ins> Setup environment </ins>


- Harvester 1.3.1 running on GIGABYTE Ampere Altra ARMv8 80 cores.
- Micro 6.0 ARM based VMs as part of the RKE2 cluster.
- 2nd GIGABYTE Ampere Altra as a worker node (SLES 15.6 ARM based).

![image](https://github.com/user-attachments/assets/bb3253d5-59ab-4584-af31-37ecb4eea1d9)

- SL Micro 6.0 based RKE2 cluster with a Rancher manager. Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster.

  
