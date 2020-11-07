az login
az account list --refresh --output table
az account set -s 'Pay-As-You-Go - MPH Analytics (Development)'

## Service Principle ID
TENANT_ID=50225b46-8a5b-4a27-b140-349ac9c7b83c
SERVICE_PRINCIPLE_ID=51e9d870-c881-4d7a-8c33-48ca617eac52
SERVICE_PRINCIPLE_SECRET=tD~-3eYMFNkv.UPFc2583y7XZd2ji~t23-

## Create Vnet and subnet for AKS
az network vnet create \
    --resource-group MPH-DDAPR-RG \
    --name DDAPR-AKS-VNET \
    --address-prefixes 10.1.0.0/16 \
    --subnet-name kubesubnet \
    --subnet-prefix 10.1.0.0/24
VNET_ID=$(az network vnet show --resource-group MPH-DDAPR-RG --name DDAPR-AKS-VNET --query id -o tsv)
SUBNET_ID=$(az network vnet subnet show --resource-group MPH-DDAPR-RG --vnet-name DDAPR-AKS-VNET --name kubesubnet --query id -o tsv)
az role assignment create --assignee $SERVICE_PRINCIPLE_ID --scope $VNET_ID --role Contributor

## Create Kubernetes Cluster
ssh-keygen -f ssh-key-ddapranaenv
az aks create --name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--service-principal $SERVICE_PRINCIPLE_ID \
--client-secret  $SERVICE_PRINCIPLE_SECRET \
--ssh-key-value ssh-key-ddapranaenv.pub \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--enable-vmss \
--kubernetes-version 1.17.11 \
--load-balancer-sku standard \
--vm-set-type VirtualMachineScaleSets \
--vnet-subnet-id $SUBNET_ID \
--location eastus \
--output table

# Create system nodepool
az aks nodepool add --name systempool \
--cluster-name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--enable-node-public-ip \
--kubernetes-version 1.17.11 \
--node-taints CriticalAddonsOnly=true:NoSchedule \
--mode System \
--node-count 1 \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Delete default nodepool and add user nodepool
# az aks nodepool delete --name sparkpool \
# --cluster-name ddapranaenv \
# --resource-group MPH-DDAPR-RG \
# --output table

az aks nodepool add --name userpool \
--cluster-name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.17.11 \
--node-count 0 \
--max-count 4 \
--min-count 0 \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create Spark node pool
az aks nodepool add --name jhubuserpool \
--cluster-name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.17.11 \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--labels hub.jupyter.org/node-purpose=user \
--node-taints hub.jupyter.org/dedicated=user:NoSchedule \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create Spark node pool
az aks nodepool add --name sparkpool \
--cluster-name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.17.11 \
--node-count 0 \
--max-count 20 \
--min-count 0 \
--node-vm-size Standard_D2s_v3 \
--vnet-subnet-id $SUBNET_ID \
--output table

# Create GPU node pool
az feature register --name GPUDedicatedVHDPreview --namespace Microsoft.ContainerService
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/GPUDedicatedVHDPreview')].{Name:name,State:properties.state}"
az provider register --namespace Microsoft.ContainerService

az aks nodepool add --name gpupool \
--cluster-name ddapranaenv \
--resource-group MPH-DDAPR-RG \
--mode user \
--enable-cluster-autoscaler \
--enable-node-public-ip \
--kubernetes-version 1.17.11 \
--node-count 0 \
--max-count 2 \
--min-count 0 \
--node-vm-size Standard_NC6 \
--aks-custom-headers UseGPUDedicatedVHD=true \
--vnet-subnet-id $SUBNET_ID \
--output table

# Kube Dashboard
kubectl delete clusterrolebinding kubernetes-dashboard
kubectl create clusterrolebinding kubernetes-dashboard \
--clusterrole=cluster-admin \
--serviceaccount=kube-system:kubernetes-dashboard \
--user=clusterUser
az aks browse --resource-group MPH-DDAPR-RG --name ddapranaenv

## Install kubectl
az aks get-credentials --name ddapranaenv \
	--resource-group MPH-DDAPR-RG \
	--output table
kubectl get node

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
ACR_NAME=ddapracr
az acr create \
	--name $ACR_NAME \
	--resource-group MPH-DDAPR-RG \
	--sku Standard \
	--admin-enabled true \
	--location eastus \
	--output table
az acr login --name $ACR_NAME
AKS_RESOURCE_GROUP=MPH-DDAPR-RG
AKS_CLUSTER_NAME=ddapranaenv
ACR_RESOURCE_GROUP=MPH-DDAPR-RG
CLIENT_ID=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)
az role assignment create --assignee $CLIENT_ID --role acrpull --scope $ACR_ID

## Setup Jupyterhub
kubectl delete namespace ddapr-jhub
kubectl delete pv --all
# Deploy PVC
JHUB_NAMESPACE=ddapr-jhub
kubectl create namespace $JHUB_NAMESPACE
ADLS_ACCOUNT_NAME=ddaprstorage
ADLS_ACCOUNT_KEY=o+mPZkOmSjI+E2ThAVKJ/66yJyGjqjV+Q12dZVENxQUqf5+T0xoTDzvxN+yJi75SRJJGB+Ct8LT9C+J3QqBt7g==
kubectl create secret generic azure-fileshare-secret --from-literal=azurestorageaccountname=$ADLS_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$ADLS_ACCOUNT_KEY -n $JHUB_NAMESPACE
kubectl apply -f pvc-pv-jhub.yaml

# Pull jupyterhub helm chart
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm fetch jupyterhub/jupyterhub --version 0.9.0

# Build customize k8s-hub image
cd jupyter-k8s-hub
docker build -t ddapracr.azurecr.io/k8s-hub:latest .
docker push ddapracr.azurecr.io/k8s-hub:latest
cd ..
cd k8s-hub-novnc-desktop
docker build -t ddapracr.azurecr.io/novnc-notebook:latest .
docker push ddapracr.azurecr.io/novnc-notebook:latest
cd ..

## Create ACR pullsecret
SPARK_NAMESPACE=ddapr-spark
kubectl create namespace $SPARK_NAMESPACE
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)
SP_PASSWD=$(az ad sp create-for-rbac --name http://$SERVICE_PRINCIPLE_ID --scopes $ACR_ID --role acrpull --query password --output tsv)
SP_APP_ID=$(az ad sp show --id http://$SERVICE_PRINCIPLE_ID --query appId --output tsv)
kubectl create secret docker-registry ddapracr-secret \
    --namespace $SPARK_NAMESPACE \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$SP_APP_ID \
    --docker-password=$SP_PASSWD

## Create service account for spark
kubectl --namespace $JHUB_NAMESPACE create serviceaccount spark-admin
kubectl create clusterrolebinding spark-role-binding \
	--clusterrole cluster-admin \
	--serviceaccount=$JHUB_NAMESPACE:spark-admin \
	--serviceaccount=$SPARK_NAMESPACE:spark-admin
kubectl --namespace $SPARK_NAMESPACE create serviceaccount spark-admin
kubectl create clusterrolebinding spark-role-binding \
	--clusterrole cluster-admin \
	--serviceaccount=$SPARK_NAMESPACE:spark-admin

# Build customized jupyterhub chart
## Install jupyterhub
helm upgrade --install ddapr-jhub jupyterhub/jupyterhub \
	--namespace $JHUB_NAMESPACE  \
	--version=0.9.0 \
	--values config.yaml \
	--timeout=5000s

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
