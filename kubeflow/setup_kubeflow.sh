#### Deploy Kubeflow on AKS
git clone --recurse-submodules https://github.com/Azure/kubeflow-aks.git
cd kubeflow-aks/manifests/
git checkout v1.7-branch
cd ..
cp -a deployments/vanilla manifests/vanilla
cd manifests/  
while ! kustomize build vanilla | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done

### Expose UI to external IP on AKS
kubectl patch service -n istio-system istio-ingressgateway -p '{"spec": {"type": "LoadBalancer"}}'
# default DNS: pitcrewkubeflow.eastus.cloudapp.azure.com

### Dummy Auth
# uname: user@example.com
# password: 12341234

### Data Storage
KF_NAMESPACE=kubeflow-user-example-com
ADLS_ACCOUNT_NAME=pitcrewstorage
ADLS_ACCOUNT_KEY=hB8d+muYJy4yUey6P4fWLEhi/iexF20seH2AIWGbw0jNq89amrbyAfYegTuTWWlXKVVGEqWpFysQJfpuOHsJbA==
kubectl create secret generic azure-fileshare-secret --from-literal=azurestorageaccountname=$ADLS_ACCOUNT_NAME --from-literal=azurestorageaccountkey=$ADLS_ACCOUNT_KEY -n $KF_NAMESPACE
kubectl apply -f kf-pvc.yaml


### Fix deleting namespace stuck
NAMESPACE=kubeflow
kubectl get namespace $NAMESPACE -o json > $NAMESPACE.json
kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f ./$NAMESPACE.json

### Fix pipeline connection issue (https://github.com/kubeflow/kubeflow/issues/5271)
kubectl edit destinationrule -n kubeflow ml-pipeline
# Modify the tls.mode (the last line) from ISTIO_MUTUAL to DISABLE
kubectl edit destinationrule -n kubeflow ml-pipeline-ui
# Modify the tls.mode (the last line) from ISTIO_MUTUAL to DISABLE





