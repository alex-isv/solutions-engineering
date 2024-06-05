# Deploying RKE2 cluster in SLES based environment

- **Installing a Rancher server on SLES**

  Please review a [quick start guide](https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli) for more details.

Install helm
````
zypper in helm
````

 
Verify the last certified k3s version >> (https://github.com/k3s-io/k3s/releases)

Install k3s:

````
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.27.10+k3s1" INSTALL_K3S_SKIP_SELINUX_RPM=true INSTALL_K3S_EXEC='server --cluster-init --write-kubeconfig-mode=644' sh -s -
````

Verify installation:
````
k3s kubectl get nodes
````
![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/1c2786fc-dc5d-405d-8e46-8cc3bb0cb3da)


````
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
````

 Install Rancher with helm

 ````
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
````
````
kubectl create namespace cattle-system 
````
````
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.crds.yaml
````
````
helm repo add jetstack https://charts.jetstack.io
````
````
helm repo update
````
````
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
````

````
kubectl get pods --namespace cert-manager
````

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/a0fc4087-b213-4443-8952-9058ffc05f13)


Verify existing release > (https://github.com/rancher/rancher/releases)


````
 helm install rancher rancher-stable/rancher --namespace cattle-system --set hostname=cl2-rancher.isv.suse --set version=2.8.2 --set replicas=1
````


Login to Rancher URL in the browser and change a password.

- **Create RKE2 cluster from the Rancher**
  
Please review [launch-kubernetes-with-rancher](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/launch-kubernetes-with-rancher#rke2) section for more details.

From Rancher server go to the Cluster Management and select RKE2 and click Custom

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/cadd344c-a1d4-4063-b1d7-308ffb3bdf14)



Click <Create> and select a proper roles and additional settings

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/e807b946-b46c-475b-9540-281d84e4eeef)



Copy a registration command and paste into the terminal of the node which are you are planning to add to the cluster.

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/89149d32-8b5a-4d78-9630-6bf41a716772)



Make sure that you have the odd number of nodes in the cluster.\
If planning to use a GPU, add a worker node with a <ins>GPU</ins> installed.


![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/8c715829-9da4-48e6-ae45-a261b4a4c2bf)



> Check if all nodes added to the cluster # ./kubectl get nodes

![image](https://github.com/alex-isv/solutions-engineering/assets/52678960/4af6220c-c235-4ddc-9904-cedc0cdb975d)
