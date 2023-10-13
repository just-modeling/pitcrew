az login
az account list --refresh --output table
az account set -s 'Azure subscription 1'

## Service Principle ID
TENANT_ID=56b3f762-b01e-4e87-be31-e4feb4fade9d
SERVICE_PRINCIPLE_ID=8aeeb2cf-0fc0-4254-9bce-7b6aba7f7e02
SERVICE_PRINCIPLE_SECRET=x.k8Q~XSwwvXzpBrU~2u8u~-yhzOxAH6HGAR.cRU

## Create Vnet and subnet for AKS
az network vnet create \
    --resource-group PITCREW-ERE-RG \
    --name PITCREW-AKS-VNET \
    --address-prefixes 10.1.0.0/16 \
    --subnet-name kubesubnet \
    --subnet-prefix 10.1.0.0/24
VNET_ID=$(az network vnet show --resource-group PITCREW-ERE-RG --name PITCREW-AKS-VNET --query id -o tsv)
SUBNET_ID=$(az network vnet subnet show --resource-group PITCREW-ERE-RG --vnet-name PITCREW-AKS-VNET --name kubesubnet --query id -o tsv)
az role assignment create --assignee $SERVICE_PRINCIPLE_ID --scope $VNET_ID --role Contributor

## Create Kubernetes Cluster
ssh-keygen -f ssh-key-pitcrew
az aks create --name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--service-principal $SERVICE_PRINCIPLE_ID \
--client-secret  $SERVICE_PRINCIPLE_SECRET \
--ssh-key-value ssh-key-pitcrew.pub \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--enable-vmss \
--kubernetes-version 1.26.6 \
--load-balancer-sku standard \
--vm-set-type VirtualMachineScaleSets \
--vnet-subnet-id $SUBNET_ID \
--location eastus \
--output table

# Create system nodepool
az aks nodepool add --name systempool \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--enable-node-public-ip \
--kubernetes-version 1.26.6 \
--node-taints CriticalAddonsOnly=true:NoSchedule \
--mode System \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Delete default nodepool pool0
az aks nodepool delete --name nodepool1 \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--output table

# Create node pool for deploying applications
az aks nodepool add --name apppool \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.26.6 \
--node-count 1 \
--max-count 4 \
--min-count 0 \
--labels dedicate.pool=apppool \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create Jupyterhub user node pool
az aks nodepool add --name jhubuserpool \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.26.6 \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--labels hub.jupyter.org/node-purpose=user dedicate.pool=jhubuserpool \
--node-taints hub.jupyter.org/dedicated=user:NoSchedule \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create Jupyterhub user large node pool
az aks nodepool add --name kfpipeline \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.26.6 \
--node-count 0 \
--max-count 10 \
--min-count 0 \
--labels dedicate.pool=pipelinepool \
--node-vm-size Standard_D4s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create Spark node pool
az aks nodepool add --name sparkpool \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--mode user \
--enable-cluster-autoscaler \
--kubernetes-version 1.26.6 \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--labels dedicate.pool=sparkpool \
--node-vm-size Standard_D8s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create GPU node pool
az feature register --name GPUDedicatedVHDPreview --namespace Microsoft.ContainerService
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/GPUDedicatedVHDPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

az aks nodepool add --name jhubgpupool \
--cluster-name pitcrewaks \
--resource-group PITCREW-ERE-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.26.6 \
--node-count 0 \
--max-count 2 \
--min-count 0 \
--labels hub.jupyter.org/node-purpose=user dedicate.pool=gpupool \
--node-taints hub.jupyter.org/dedicated=user:NoSchedule \
--node-vm-size Standard_NC6 \
--aks-custom-headers UseGPUDedicatedVHD=true \
--vnet-subnet-id $SUBNET_ID \
--output table

# Kube Upgrade
az aks nodepool update --cluster-name pitcrewaks \
	--resource-group PITCREW-ERE-RG \
	--name jhubuserpool --disable-cluster-autoscaler 
az aks nodepool update --cluster-name pitcrewaks \
	--resource-group PITCREW-ERE-RG \
	--name jhubuserpool \
	--enable-cluster-autoscaler \
	--max-count 20 \
	--min-count 0

## Install kubectl
az aks get-credentials --name pitcrewaks \
	--resource-group PITCREW-ERE-RG \
	--output table
kubectl get node

# Kube Dashboard
kubectl delete clusterrolebinding kubernetes-dashboard
kubectl create clusterrolebinding kubernetes-dashboard \
--clusterrole=cluster-admin \
--serviceaccount=kube-system:kubernetes-dashboard \
--user=clusterUser
az aks browse --name pitcrewaks --resource-group PITCREW-ERE-RG


## Set up Helm 3
# Mac OS
curl https://get.helm.sh/helm-v3.1.0-darwin-amd64.tar.gz > helm-v3.1.0.tar.gz
tar -zxvf helm-v3.1.0.tar.gz
mv darwin-amd64/helm /usr/local/bin/helm
# Linux
curl https://get.helm.sh/helm-v3.1.0-linux-amd64.tar.gz > helm-v3.1.0.tar.gz 
tar -zxvf helm-v3.1.0.tar.gz
mv linux-amd64/helm /usr/local/bin/helm

## Setup a separate ACR
ACR_NAME=pitcrewacr
az acr create \
	--name $ACR_NAME \
	--resource-group PITCREW-ERE-RG \
	--sku Standard \
	--admin-enabled true \
	--location eastus \
	--output table
az acr login --name $ACR_NAME
AKS_RESOURCE_GROUP=PITCREW-ERE-RG
AKS_CLUSTER_NAME=pitcrewaks
ACR_RESOURCE_GROUP=PITCREW-ERE-RG
CLIENT_ID=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)
az role assignment create --assignee $CLIENT_ID --role acrpull --scope $ACR_ID

## Setup Jupyterhub
kubectl delete namespace pitcrew-jhub
kubectl delete pv --all
# Deploy PVC
JHUB_NAMESPACE=pitcrew-jhub
kubectl create namespace $JHUB_NAMESPACE
ADLS_ACCOUNT_NAME=pitcrewstorage
ADLS_ACCOUNT_KEY=hB8d+muYJy4yUey6P4fWLEhi/iexF20seH2AIWGbw0jNq89amrbyAfYegTuTWWlXKVVGEqWpFysQJfpuOHsJbA==
kubectl create secret generic azure-fileshare-secret --from-literal=azurestorageaccountname=$ADLS_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$ADLS_ACCOUNT_KEY -n $JHUB_NAMESPACE
kubectl apply -f pvc-pv-jhub.yaml

# Pull jupyterhub helm chart
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update

# Build customize k8s-hub image
# cd jupyter-k8s-hub
# docker build -t pitcrewacr.azurecr.io/k8s-hub:1.2.0 .
# docker push pitcrewacr.azurecr.io/k8s-hub:1.2.0
# cd ..
# cd k8s-hub-novnc-desktop
# docker build -t pitcrewacr.azurecr.io/novnc-notebook:2.0.0 .
# docker push pitcrewacr.azurecr.io/novnc-notebook:2.0.0
# cd ..
cd k8s-hub-novnc-desktop
docker build -t pitcrewacr.azurecr.io/novnc-notebook:latest .
docker push pitcrewacr.azurecr.io/novnc-notebook:latest
cd ..

## Create ACR pullsecret
ACR_NAME=pitcrewacr
AKS_RESOURCE_GROUP=PITCREW-ERE-RG
AKS_CLUSTER_NAME=pitcrewaks
ACR_RESOURCE_GROUP=PITCREW-ERE-RG
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)
SP_PASSWD=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPLE_ID --scopes $ACR_ID --role acrpull --query password --output tsv)
SP_APP_ID=$(az ad sp show --id http://$SERVICE_PRINCIPLE_ID --query appId --output tsv)
kubectl create secret docker-registry pitcrewacr-secret \
    --namespace $JHUB_NAMESPACE \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$SP_APP_ID \
    --docker-password=$SP_PASSWD

## Create service account for spark
kubectl delete clusterrolebinding spark-role-binding
kubectl --namespace $JHUB_NAMESPACE create serviceaccount spark-admin
kubectl create clusterrolebinding spark-role-binding --clusterrole cluster-admin --serviceaccount=$JHUB_NAMESPACE:spark-admin

# Build customized jupyterhub chart
## Install jupyterhub
helm upgrade --cleanup-on-fail \
	--install pitcrew-jhub jupyterhub/jupyterhub \
	--namespace $JHUB_NAMESPACE  \
	--version=3.1.0 \
	--values config.yaml \
	--timeout=5000s

kubectl -n pitcrew-jhub get pods | grep Pending | cut -d' ' -f 1 | xargs kubectl -n pitcrew-jhub delete pod

## Install Gitlab
## Need DNS service configured first https://docs.gitlab.com/charts/installation/deployment.html
# GITLAB_NAMESPACE=hhs-gitlab
# kubectl create ns $GITLAB_NAMESPACE
# kubectl create secret generic gitlab-db-secret --from-literal=username=mphhubadmin@mphhubdbs1 --from-literal=password='Simple123!' -n $GITLAB_NAMESPACE
# helm repo add gitlab https://charts.gitlab.io/
# helm repo update
# helm upgrade --install hhs-gitlab gitlab/gitlab \
# 	--namespace $GITLAB_NAMESPACE  \
# 	--set global.edition=ce \
# 	--set global.imagePullPolicy=Always \
# 	--set certmanager-issuer.email=zjia@ksmconsulting.com \
# 	--set postgresql.install=false \
# 	--set global.psql.host=mphhubdbs1.postgres.database.azure.com \
# 	--set global.psql.password.secret=gitlab-db-secret \
# 	--set global.psql.password.key=password \
# 	--set global.psql.database=hhs_gitlab \
# 	--set global.psql.username=mphhubadmin@mphhubdbs1 \
# 	--timeout=5000s

## Setup auto-reboot
#kubectl apply -f https://github.com/weaveworks/kured/releases/download/1.2.0/kured-1.2.0-dockerhub.yaml

## Upgrade
#az aks upgrade --resource-group MPH-Analytics-RG --name mphanaenv --kubernetes-version 1.13.10
#az aks show --resource-group MPH-Analytics-RG --name mphanaenv --output table
