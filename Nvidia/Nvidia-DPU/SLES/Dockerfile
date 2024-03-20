from registry.suse.com/suse/sle15:latest

WORKDIR /root/workspace

ADD create_bfb .
ADD install.sh .
ADD bootimages bootimages/
ADD qemu-aarch64-static /usr/bin/

#RUN zypper ref

RUN zypper -n in SUSEConnect

# Add a registration code or use RMT server

# RUN SUSEConnect --regcode INTERNAL-USE-ONLY-****
ADD http://192.168.150.160/repo/rmt-server.crt /etc/pki/trust/anchors/rmt.crt

# Note: <ADD http://...>  is the IP of the local RMT server.
# You need to post rmt-server.crt file on your RMT server in the location which can be reachable from url
# So, on our local RMT server copy /etc/rmt/ssl/rmt-server.crt file to the /usr/share/rmt/public/repo directory, which creates symb link to ./var/lib/rmt/public/repo which is a public repo of RMT server. 
# Setup a proper permission to /usr/share/rmt/public/repo directory 
# Sync rmt server.


RUN zypper ref
RUN zypper --non-interactive up
RUN zypper -n in grub2-arm64-efi grub2-branding-SLE
RUN zypper -n in kernel-default
RUN zypper -n in dhcp-client
RUN zypper -n in parted wget dosfstools
RUN zypper -n in dracut-kiwi-lib dracut-kiwi-oem-repart
RUN zypper -n in usbutils pciutils binutils
RUN zypper -n in shim sudo which openssh vim
RUN zypper --non-interactive in insserv-compat libstdc++6-devel-gcc7 make lsof tk tcl expat libgfortran4 mstflint
RUN zypper -n in ethtool
RUN zypper -n rm  kernel-firmware-nvidia-gspx-G06
RUN /usr/bin/dracut -f --regenerate-all

#RUN zypper --non-interactive in systemd-network ethtool
#RUN zypper --non-interactive in NetworkManager
RUN /usr/bin/dracut -f --regenerate-all

#RUN zypper --non-interactive in wicked wicked-service
#RUN zypper --non-interactive mstflint

RUN rpm -ihv --force /root/workspace/bootimages/mlxbf-bootimages-*.aarch64.rpm || true
RUN rpm -ivh --nodeps /root/workspace/bootimages/mlxbf-bfscripts-*.noarch.rpm || true

#for debug
#RUN /root/workspace/create_bfb

CMD /root/workspace/create_bfb
