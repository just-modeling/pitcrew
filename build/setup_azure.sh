az login
az account list --refresh --output table
az account set -s 'Pay-As-You-Go - MPH Analytics'
az acr login -n mphanaenvacr
az acr helm repo add -n mphanaenvacr

## Install kubectl
az aks get-credentials --name mphanaenv \
	--resource-group MPH-Analytics-RG \
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

## Setup a separate ACR for NOVNC
ACR_NAME=novncacr
az acr create \
	--name $ACR_NAME \
	--resource-group MPH-Analytics-RG \
	--sku Standard \
	--admin-enabled true \
	--location eastus2 \
	--output table
az acr login --name $ACR_NAME
AKS_RESOURCE_GROUP=MPH-Analytics-RG
AKS_CLUSTER_NAME=mphanaenv
ACR_RESOURCE_GROUP=MPH-Analytics-RG
CLIENT_ID=$(az aks show --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "servicePrincipalProfile.clientId" --output tsv)
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $ACR_RESOURCE_GROUP --query "id" --output tsv)
az role assignment create --assignee $CLIENT_ID --role acrpull --scope $ACR_ID

## Setup Jupyterhub
# Deploy PVC
JHUB_NAMESPACE=hhs-jhub
kubectl create namespace $JHUB_NAMESPACE
ADLS_ACCOUNT_NAME=zus2mphdevstorage2
ADLS_ACCOUNT_KEY=QibSc1RlGdrpxVBHNR+B96XHPclVfLW9U1exOKlyrczZLdL0Q8efWTOEa6XtXnDS9K9nXURPZYhziy+Od/WrfA==
kubectl create secret generic azure-fileshare-secret --from-literal=azurestorageaccountname=$ADLS_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$ADLS_ACCOUNT_KEY -n $JHUB_NAMESPACE
kubectl apply -f pvc-pv-jhub.yaml
# Pull jupyterhub helm chart
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
helm repo update
helm fetch jupyterhub/jupyterhub --version 0.8.2

# Build customized jupyterhub chart
## Install jupyterhub
helm upgrade --install hhs-jhub jupyterhub/jupyterhub \
	--namespace $JHUB_NAMESPACE  \
	--version 0.9.0-beta.4 \
	--values config.yaml \
	--timeout=5000s

## Install Gitlab
## Need DNS service configured first https://docs.gitlab.com/charts/installation/deployment.html
GITLAB_NAMESPACE=hhs-gitlab
kubectl create ns $GITLAB_NAMESPACE
kubectl create secret generic gitlab-db-secret --from-literal=username=mphhubadmin@mphhubdbs1 --from-literal=password='Simple123!' -n $GITLAB_NAMESPACE
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm upgrade --install hhs-gitlab gitlab/gitlab \
	--namespace $GITLAB_NAMESPACE  \
	--set global.edition=ce \
	--set global.imagePullPolicy=Always \
	--set certmanager-issuer.email=zjia@ksmconsulting.com \
	--set postgresql.install=false \
	--set global.psql.host=mphhubdbs1.postgres.database.azure.com \
	--set global.psql.password.secret=gitlab-db-secret \
	--set global.psql.password.key=password \
	--set global.psql.database=hhs_gitlab \
	--set global.psql.username=mphhubadmin@mphhubdbs1 \
	--timeout=5000s

## Setup auto-reboot
#kubectl apply -f https://github.com/weaveworks/kured/releases/download/1.2.0/kured-1.2.0-dockerhub.yaml

## Upgrade
#az aks upgrade --resource-group MPH-Analytics-RG --name mphanaenv --kubernetes-version 1.13.10
#az aks show --resource-group MPH-Analytics-RG --name mphanaenv --output table
