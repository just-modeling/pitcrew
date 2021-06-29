export KF_NAME=kubeflow-az
export BASE_DIR=~/just-modeling/pitcrew/kubeflow/deployment
export KF_DIR=${BASE_DIR}/${KF_NAME}
export CONFIG_URI="https://raw.githubusercontent.com/kubeflow/manifests/v1.2-branch/kfdef/kfctl_k8s_istio.v1.2.0.yaml"
mkdir -p ${KF_DIR}
cd ${KF_DIR}
kfctl build -V -f ${CONFIG_URI}
kfctl apply -V -f kfctl_k8s_istio.v1.2.0.yaml

### Fix deleting namespace stuck
NAMESPACE=kubeflow
kubectl get namespace $NAMESPACE -o json > $NAMESPACE.json
kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f ./$NAMESPACE.json
## 40.76.165.52
## pitcrew-kubeflow.eastus.cloudapp.azure.com

### Fix pipeline connection issue (https://github.com/kubeflow/kubeflow/issues/5271)
kubectl edit destinationrule -n kubeflow ml-pipeline
# Modify the tls.mode (the last line) from ISTIO_MUTUAL to DISABLE
kubectl edit destinationrule -n kubeflow ml-pipeline-ui
# Modify the tls.mode (the last line) from ISTIO_MUTUAL to DISABLE

### Expose UI to external IP on AKS
kubectl patch service -n istio-system istio-ingressgateway -p '{"spec": {"type": "LoadBalancer"}}'







