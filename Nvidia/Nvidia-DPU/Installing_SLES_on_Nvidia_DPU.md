# Installing SLES 15 on Nvidia DPU

## Installing SLES 15 on Nvidia BlueField-2 card

Review (https://github.com/Mellanox/bfb-build/)

**Installing a Rancher server on DPU**

Check releases > (https://github.com/k3s-io/k3s/releases)

Latest k3s version as of today *3-19-24* >  v1.28.7+k3s1

1. zypper in helm
2. curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.11+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
3. export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
4. helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
5. kubectl create namespace cattle-system
6. kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml
7. helm repo add jetstack https://charts.jetstack.io
8. helm repo update
9. helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
10. kubectl get pods --namespace cert-manager
11. helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=dpu1.isv.suse --set version=2.8.3 --set replicas=1


