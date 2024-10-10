# Installing SLES or SL Micro on Nvidia DPU 

**EXPERIMENTAL, PROOF OF CONCEPT. Don't use as the official reference**

## Installing SLES on Nvidia BlueField-2 card

### Prerequisites ###


Review (https://github.com/Mellanox/bfb-build/) and modify a bfb-build and a DOCKER file with proper values.

If installing OS from the host, install *rshim* on the host and enable it.

````
zypper in rshim
````
````
systemctl enable rshim
````

````
systemctl start rshim
````

verify that rshim is running

````
systemctl status rshim
````

On the host machine:

For Arm systems >>

````
wget https://www.mellanox.com/downloads/DOCA/DOCA_v2.5.0/doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.aarch64.rpm
````
````
rpm -Uvh doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.aarch64.rpm
````
````
zypper refresh 

````

````
sudo zypper install doca-ofed
````

For x86 >>

````
wget https://www.mellanox.com/downloads/DOCA/DOCA_v2.5.0/doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.x86_64.rpm
````
````
rpm -Uvh doca-host-repo-sles15sp5-2.5.0-0.0.1.23.10.1.1.9.0.x86_64.rpm
````
````
zypper refresh
````
````
sudo zypper install doca-ofed
````


Review [Installation files section](https://docs.nvidia.com/doca/sdk/nvidia+doca+installation+guide+for+linux/index.html#installation-files) for a proper doca package.


### Installation steps ###

Clone a bfb-build from Mellanox git page.

````
git clone https://github.com/Mellanox/bfb-build
````

````
cd bfb-build
````
Make sure that your host node has *picocom* or *minicom* installed to access a DPU through rshim.

From DPU's uefi disable secure boot.
````
picocom /dev/rshim0/console
````
Use the following serial settings:


![image](https://github.com/user-attachments/assets/66719abe-e588-470c-a337-279650c8a00d)


where rshim0 is the proper DPU.

In this test example a host node has 3 DPUs installed, so should have 3 rshim devices listed:

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/d5b92529-164e-4659-978c-061b0ce9e0be)


Modify a Dockerfile and bfb-build file according to your OS release. See attached example Dockerfile for SLES.

install a podman

````
zypper in podman
````


To build a .bfb image run:

````
./bfb-build
````
that will create an image in the */tmp/distro/version.pid* directory

To install an image on DPU run:

````
 echo "SW_RESET 1" > /dev/rshim0/misc
````
which should reset a DPU device and


````
./bfb-install -b /tmp/sles15.5.2601/sles.bfb -r rshim1
````
to push an image to DPU.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ce6f6da1-58a5-4880-9f0a-88d6a819704c)



> [!NOTE]
> These steps validated for BlueField-2 and BlueField-3 with SLES SP6 container image.
>  



![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/3f2776a1-9ed3-4a7e-a979-e6fe8f0f6503)

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/ce27a886-9f3c-46a8-8dbd-ee39348b4f9d)


>[!NOTE]
>If your host OS didn't have *DOCA_OFED* installed as mentioned above you can include MLNX_OFED drivers in your Dockerfile definition or download MLNX_OFED drivers for SLES sp5 ARM from ([https://network.nvidia.com/product/infiniband-drivers/linux/mlnx_ofed/](https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/)) and install on DPU directly to enable fast interface on SLES. MLNX_OFED drivers for SLES sp6 ARM will become available soon.
>
>Review ([Installing MLNX_OFED](https://docs.nvidia.com/networking/display/mlnxofedv24010331/installing+mlnx_ofed))
>
>untar downloaded package:
>````
>tar xzf MLNX_OFED_LINUX-23.10-1.1.9.0-sles15sp5-aarch64.tgz
>````
>install drivers with:
>````
>./mlnxofedinstall
>````

## Using Nvidia BlueField-3 with SLE Micro 6.0 or SLES 15 sp6 ##

>[!NOTE]
>BlueField-3 requires additional eMMC drivers which become available with SLES SP6 or Micro 6.0.
>For SLE Micro another installation method should be used with a raw image and a custom script.

Download .raw.xz image (arm64 version) of SLES 15sp6 or Micro 6.0.

<ins>To make a .bfb file</ins> download a custom script ./mk-slemicro-bfb.sh (attached in the SLES directory of the current Github page) and run it as:

````
./mk-slemicro-bfb-v2.sh ./SLES15-SP6-Minimal-Image.aarch64-RaspberryPi-RC1-202403.raw.xz* 
````
(or Micro 6.0 raw.xz image).


<ins>To install a *.bfb* image on DPU</ins> use the following command :

````
./bfb-install -b ./SLES15-SP6-Minimal-Image.aarch64-RaspberryPi-RC1-202403.raw.bfb -r rshim0* 
````
(or Micro 6.0 bfb file).


From the 2nd terminal start minicom.

Wait until `sh-4.4#` shell appear and enter the following command:


````
dd bs=4M if=/OS.raw of=/dev/nvme0n1 iflag=fullblock oflag=sync
````

Once the DPU rebooted, on boot press ‘e’ and replace *console=ttyS0* to *console=hvc0* in the grub.

>[!NOTE]
> That *console* prereq. will be fixed in later versions. It also can be modified and customized with the original .raw image.
>

After boot you have to update/add the same console=hvc0 in `/etc/default/grub` and execute:

On SP6: 
````
grub2-mkconfig -o /boot/grub/grub.cfg
````

On SLE-Micro:
````
transactional-update grub.cfg
````

The default credentials are *root/linux*.

Configure a network according to your needs.

*below is the example of SLE MICRO 6.0 with a cockpit console installed on the BlueField-3*

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/10818af0-f1bc-4313-9990-a20d59539214)







