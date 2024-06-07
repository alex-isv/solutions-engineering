   *Build SLES based OpenVino container*
(in progress..)

- Install podman
````
zypper in podman
````

- Build a container (make sure that Dockerfile is in the same direcrory). Dockerfile sample is available under OpenVino directory. Use your own regcode in the Dockerfile or RMT server. See examples how to register > https://github.com/SUSE/container-suseconnect

````
podman build -t openvino .
````
