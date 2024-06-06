# Creating a container based Nvidia GPU driver

> [!NOTE]
> This guidance is not providing any support.
> Steps are publicly available from Nvidia Github page [gpu-driver-container for sle15](https://github.com/NVIDIA/gpu-driver-container/tree/main/sle15), but modified with the latest versions.
>
> 
## Purpose
These steps outlines building process of the container based Nvidia GPU driver for SUSE Linux Enterprise Server in the large Kubernetes environment.
For more details, please review section [Building the container image](https://documentation.suse.com/trd/kubernetes/pdf/gs_rke2-slebci_nvidia-gpu-operator_en.pdf#%5B%7B%22num%22%3A80%2C%22gen%22%3A0%7D%2C%7B%22name%22%3A%22XYZ%22%7D%2C63.779%2C450.553%2Cnull%5D)

- Clone the NVIDIA driver GitHub repository and change to the driver/sle15 directory

````
git clone https://github.com/NVIDIA/gpu-driver-container.git && cd gpu-driver-container/sle15/
````

Open a Dockerfile and set <INS>CUDA_VERSION</ins> to 12.4 and <ins>golang</ins> version to 1.22 
> [!NOTE]
> Check the latest available version for CUDA and golang.
>  For this particular example CUDA 12.4.1 with golang 1.22 and a driver version 550.54.15 were validated with SLES15 sp5.

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
If pushing directly to the private or public registry, the following commands can be used.

In the below example the <ins>ghcr.io</ins> is used as a public container registry.
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

Check if the container is listed on the registry.

````
podman search --list-tags ghcr.io/alex-isv/nvidia-gpu-driver-sle15sp5-550.54.15:latest
````
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/45d5c214-a136-4301-abad-9ca96360702b)

- Running a container locally.
  
````
sudo podman run -d --name driver.sle15sp5-550.54.15  --privileged --pid=host -v /run/nvidia:/run/nvidia:shared -v /var/log:/var/log --restart=unless-stopped ghcr.io/alex-isv/nvidia-gpu-driver-sle15sp5-550.54.15 
````
Verify if a container was deployed.
````
sudo podman logs -f driver.sle15sp5-550.54.15
````


Check if a container can see a GPU.

````
sudo podman exec -it  driver.sle15sp5-550.54.15 nvidia-smi
````


  ![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9cf7b43c-6f98-4c93-af07-bb612e8366e0)

