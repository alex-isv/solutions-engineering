# Creating container based Nvidia GPU driver

Clone the NVIDIA driver GitHub repository and change to the driver/sle15 directory

````
git clone https://github.com/NVIDIA/gpu-driver-container.git && cd gpu-driver-container/sle15/
````

Open a Dockerfile and set <INS>CUDA_VERSION</ins> to 12.4 and <ins>golang</ins> version to 1.22

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5df93be4-76cd-4cef-aff8-a490fbd9d12d)

Build a driver

> [!NOTE]
> As of June 2024 the latest version of the available driver was used.
> Please validate a driver and a CUDA version during your deployment as they can be different. 

````
podman build -t nvidia-gpu-driver-sle15sp5-550.54.15 \
    --build-arg DRIVER_VERSION="550.54.15" \
    --build-arg CUDA_VERSION="12.4.1" \
    --build-arg SLES_VERSION="15.5" \
    .
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/2fffc3f7-b358-4713-8c77-03c65210cb4b)


> [!TIP]
> Before installing new drivers, make sure to remove older versions of CUDA Toolkit and Nvidia drivers:
````
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"
````

````
sudo zypper remove "*nvidia*"
````
