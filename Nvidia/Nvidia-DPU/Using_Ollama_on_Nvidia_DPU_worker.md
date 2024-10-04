# Utilization of Nvidia BlueField-3 arm cores with Ollama-OpenWebUi.

> [!NOTE]
> This is not the official reference. Used only as a proof of concept.
> Nvidia's DPUs are not designed for that purpose.

<ins>Setup environment:</ins>

![image](https://github.com/user-attachments/assets/e85c5fe7-6877-4c49-8048-b0fbfc2df1e7)


- RKE2 cluster with ARM based nodes (SLE Micro 6.0 based) managed by a Rancher server running on Nvidia BlueField-2 (Micro 6.0 Arm).
  
  ( Please review [Deploying RKE2 cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Rancher/RKE2_cluster_deployment.md#deploying-rke2-cluster-in-sles-based-environment ) guide on how to install RKE2 cluster.)

- Nvidia BluedField-3 as a worker node (Micro 6.0) 16 arm cores total.

## Install Open WebUI with Helm

Review steps on how to install [Ollama with OpenWebUI](https://github.com/alex-isv/solutions-engineering/blob/main/ARM/Running_Ollama_OpenWebUI_on_SUSE_RKE2_cluster_with_Ampere_ARM_worker.md#install-open-webui-with-helm)

Sample performance with num_thread (Ollama) set to 12 and llama3.1 model.

![image](https://github.com/user-attachments/assets/9929bb82-fdef-4f61-9c70-ce4c0d596303)


![image](https://github.com/user-attachments/assets/fb25e01d-cac2-46ec-a96b-0837f614e165)


![image](https://github.com/user-attachments/assets/d4c98960-46d6-4582-94c2-dfcc780926e5)



