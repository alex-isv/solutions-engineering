# Creating container based Nvidia GPU driver

Clone the NVIDIA driver GitHub repository and change to the driver/sle15 directory

````
git clone https://github.com/NVIDIA/gpu-driver-container.git && cd gpu-driver-container/sle15/
````

Open a Dockerfile and set <INS>CUDA_VERSION</ins> to 12.4 and <ins>golang</ins> version to 1.22

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5df93be4-76cd-4cef-aff8-a490fbd9d12d)

