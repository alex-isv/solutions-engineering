# Utilization of Nvidia BlueField-3 arm cores with Ollama-OpenWebUi.

> [!NOTE]
> This is not the official reference. Used only as a proof of concept.

<ins>Setup environment:</ins>

- RKE2 cluster with arm based nodes (SLE Micro 6.0 based) managed by a Rancher server running on Nvidia BlueField 2 (Micro 6.0).

- Nvidia BluedField-3 as a worker node (Micro 6.0) 16 arm cores total.


Sample performance with default num_thread = 2 Ollama.

![image](https://github.com/user-attachments/assets/38e80e01-6e2f-487d-b14e-b18dfd9a4cc5)

