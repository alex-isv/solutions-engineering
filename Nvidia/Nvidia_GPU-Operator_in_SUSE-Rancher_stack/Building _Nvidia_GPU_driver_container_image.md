# Creating a container based Nvidia GPU driver

> [!NOTE]
> This guidance is not providing any support.
> Steps are publicly available from Nvidia Github page [gpu-driver-container for sle15](https://github.com/NVIDIA/gpu-driver-container/tree/main/sle15), but modified with the latest versions. These steps were validated for Nvidia GPU A100 and H100.
>
> 
## Purpose
These steps outlines building process of the container based Nvidia GPU driver for SUSE Linux Enterprise Server in the large Kubernetes environment.
For more details, please review section [Building the container image](https://documentation.suse.com/trd/kubernetes/pdf/gs_rke2-slebci_nvidia-gpu-operator_en.pdf#%5B%7B%22num%22%3A80%2C%22gen%22%3A0%7D%2C%7B%22name%22%3A%22XYZ%22%7D%2C63.779%2C450.553%2Cnull%5D)

- Prerequisites:
  
  Install the folowing on the host:
  
````
sudo zypper install \
kernel-firmware-nvidia \
kernel-firmware-nvidia-gspx-G06 \
libnvidia-container-tools \
libnvidia-container1 \
nvidia-container-runtime \
sle-module-NVIDIA-compute-release
````

> [!NOTE]
> Make sure that the kernel-firmware-nvidia-gsp-G06 version is matching the driver's version.
> For ex. if installing a driver version 550.90.07, you need to install kernel-firmware-nvidia-gspx-G06-550.90.07-150500.11.29.1

- Clone the NVIDIA driver GitHub repository and change to the driver/sle15 directory

````
git clone https://github.com/NVIDIA/gpu-driver-container.git && cd gpu-driver-container/sle15/
````

Open a Dockerfile and set <ins>CUDA</ins> version to 12.4 and <ins>golang</ins> version to 1.22 
> [!NOTE]
> Check the latest available version for CUDA and golang.
>  For this particular example CUDA 12.4.1 with golang 1.22 and a driver version 550.54.15 were validated with SLES15 sp5.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/5df93be4-76cd-4cef-aff8-a490fbd9d12d)



> [!NOTE]
> As of June 2024 the latest version of the available driver was used.
> Please validate a driver and a CUDA version during your deployment as they can be different.
> 
> The kernel validated in this setup is **_5.14.21-150500.55.62-default_**.
> Due to the `nvidia-driver` script issue as described in [sle15/nvidia-driver fails to parse correct kernel version](https://gitlab.com/nvidia/container-images/driver/-/issues/52) the workaround should be used to update the `nvidia-driver` script.
> 
> Run the following command:
>  ````
> if grep -q 'grep "Basesystem"' nvidia-driver; then   echo "The change has already been made.";   else   sed -i 's/\(grep \$version_without_flavor \)/\1| grep "Basesystem" /' nvidia-driver;   echo "The change has been applied."; fi
>  
> ````

- Build a local driver

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


Make sure that

````
sudo lsmod | grep nvidia
````
is not returning any values.
If anything is listed, remove nvidia with a below commands and reboot the server.


> [!TIP]
> Before installing new drivers, make sure to remove older versions of CUDA Toolkit and Nvidia drivers:
````
sudo zypper remove "cuda*" "*cublas*" "*cufft*" "*cufile*" "*curand*" \
 "*cusolver*" "*cusparse*" "*gds-tools*" "*npp*" "*nvjpeg*" "nsight*" "*nvvm*"
````

````
sudo zypper remove "*nvidia*"
````


- Running a container locally.
  
````
sudo podman run -d --name driver.sle15sp5-550.54.15  --privileged --pid=host -v /run/nvidia:/run/nvidia:shared -v /var/log:/var/log --restart=unless-stopped ghcr.io/alex-isv/nvidia-gpu-driver-sle15sp5-550.54.15 
````
Verify if a container was deployed.
````
sudo podman logs -f driver.sle15sp5-550.54.15
````
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9b4a72e5-188b-4d2f-8f06-677b964fbb29)


Check if a container can see a GPU.

````
sudo podman exec -it  driver.sle15sp5-550.54.15 nvidia-smi
````


  ![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/9cf7b43c-6f98-4c93-af07-bb612e8366e0)

To delete a local container, execute:
````
podman stop driver.sle15sp5-550.54.15
````
and
````
podman rm driver.sle15sp5-550.54.15
````

### If building a gpu-driver container for the Nvidia gpu-operator use the following steps:
  

In the below example the <ins>ghcr.io</ins> is used as a public container registry.
````

podman build -t ghcr.io/alex-isv/nvidia-sle15sp5-550.54.15 \
--build-arg DRIVER_VERSION="550.54.15" \
--build-arg CUDA_VERSION="12.4.1" \
--build-arg SLES_VERSION="15.5" \
.

````
Tag with the following command:

````
podman tag ghcr.io/alex-isv/nvidia-sle15sp5-550.54.15:latest ghcr.io/alex-isv/driver:550.54.15-sles15.5

````

  
Push to the registry
````
podman push ghcr.io/alex-isv/nvidia-sle15sp5-550.54.15:latest && podman push ghcr.io/alex-isv/driver:550.54.15-sles15.5
````

Check if the container is listed on the registry.

````
podman search --list-tags ghcr.io/alex-isv/driver
````
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/694a8968-97b1-42a3-ad81-7a67e9d8a1ac)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/45d5c214-a136-4301-abad-9ca96360702b)

For the testing purpose a pre-build container driver version 550.54.15 is available to try from:

````
podman pull ghcr.io/alex-isv/driver:550.54.15-sles15.5
````


To deploy Nvidia gpu-operator follow [Deploying Nvidia GPU-Operator in SLES based cluster](https://github.com/alex-isv/solutions-engineering/blob/main/Nvidia/Nvidia_GPU-Operator_in_SUSE-Rancher_stack/Installing_Nvidia_GPU-Operator_in_SLE_based_RKE2_cluster.md#deploying-nvidia-gpu-operator-in-sles-based-rke2-cluster).

