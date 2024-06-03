   *Build SLES based OpenVino container*
(in progress..)

- Install podman
````
zypper in podman
````

- Build a container (make sure that Dockerfile is in the same direcrory). SLES.dockerfile sample is available under OpenVino directory. Rename SLES.dockerfile to Dockerfile and use your own regcode in the Dockerfile. See examples how to register > https://github.com/SUSE/container-suseconnect

````
podman build -t openvino .
````
