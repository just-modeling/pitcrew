## Install kubectl & get credentials
aws eks update-kubeconfig --name hhs-tf-dev-eks
kubectl get node

## Set up Helm 3
# Mac OS
curl https://get.helm.sh/helm-v3.1.0-darwin-amd64.tar.gz > helm-v3.1.0.tar.gz
tar -zxvf helm-v3.1.0.tar.gz
mv darwin-amd64/helm /usr/local/bin/helm

# Set up PVC
NFS_NAMESPACE=hhs-nfs-server
kubectl create namespace $NFS_NAMESPACE
helm install hhs-nfs stable/nfs-server-provisioner --namespace=$NFS_NAMESPACE \
    --set=persistence.enabled=true,persistence.storageClass=gp2,persistence.size=500Gi,storageClass.name=hhs-nfs,storageClass.provisionerName=hhs/nfs-server

## Setup Jupyterhub
JHUB_NAMESPACE=hhs-jhub
kubectl create namespace $JHUB_NAMESPACE
kubectl apply -f pvc-nfs-jhub.yaml

## Build customized jupyterhub chart
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update

## Modify yaml file in jupyterhub if customization need
# helm fetch jupyterhub/jupyterhub --version 0.8.2

## Install jupyterhub
helm upgrade --install hhs-jhub jupyterhub/jupyterhub \
	--namespace $JHUB_NAMESPACE  \
    --version 0.8.2 \
	--values config-aws.yaml \
	--timeout=5000s

## Feel free to add your gitlab deployment code here

## Purge
# helm uninstall hhs-jhub -n hhs-jhub
# kubectl delete ns $JHUB_NAMESPACE 