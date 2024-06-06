# Creating container based Nvidia GPU driver

## Purpose
These steps outlines building process of the container based Nvidia GPU driver for SUSE Linux Enterprise Server in the large Kubernetes environment.
For more details, please review section [Building the container image](https://documentation.suse.com/trd/kubernetes/pdf/gs_rke2-slebci_nvidia-gpu-operator_en.pdf#%5B%7B%22num%22%3A80%2C%22gen%22%3A0%7D%2C%7B%22name%22%3A%22XYZ%22%7D%2C63.779%2C450.553%2Cnull%5D)

- Clone the NVIDIA driver GitHub repository and change to the driver/sle15 directory

````
git clone https://github.com/NVIDIA/gpu-driver-container.git && cd gpu-driver-container/sle15/
````

Open a Dockerfile and set <INS>CUDA_VERSION</ins> to 12.4 and <ins>golang</ins> version to 1.22

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5df93be4-76cd-4cef-aff8-a490fbd9d12d)

- Build a driver

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

Check with 
````
podman images
````


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d79609e7-13c5-4197-89a2-d54d295357cb)


> [!TIP]
> Before installing new drivers, make sure to remove older versions of CUDA Toolkit and Nvidia drivers:
````
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"
````

````
sudo zypper remove "*nvidia*"
````
If building directly in the registry, the following command can be used.

For the ghcr.io example
````
podman build -t ghcr.io/alex-isv/nvidia-gpu-driver-sle15sp5-550.54.15:latest \
--build-arg DRIVER_VERSION="550.54.15" \
--build-arg CUDA_VERSION="12.4.1" \
--build-arg SLES_VERSION="15.5" \
    .
````
````
podman push ghcr.io/alex-isv/nvidia-gpu-driver-sle15sp5-550.54.15:latest
````
