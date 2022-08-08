# Legacy set up for vault - Depricated

## Vault Install 
```
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm -n vault install vault hashicorp/vault --set "global.openshift=true" --set "server.dev.enabled=true" --create-namespace
```

## Vault setup  - Development mode
```
kubectl exec vault-0 -n vault -- vault auth enable kubernetes

oc -n vault rsh vault-0

vault write auth/kubernetes/config \
  issuer="https://kubernetes.default.svc.cluster.local" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault secrets enable -path=avp -version=2 kv
exit

oc project vault
oc cp secrets/license.json vault-0:/tmp/
oc rsh vault-0
vault kv put  avp/test sample=@/tmp/license.json

cat << EOF > /tmp/policy.hcl 
path "avp/data/test" { capabilities = ["read"] } 
EOF

vault policy write argocd-repo-server /tmp/policy.hcl

vault write auth/kubernetes/role/argocd-repo-server \
	bound_service_account_names=argocd-repo-server \
  bound_service_account_namespaces=openshift-gitops policies=argocd-repo-server

```
## Useful command to login to argo cd server

```
oc get routes -n openshift-gitops | grep redhat-kong-gitops-server | awk '{print $2}'
export ARGOCD_SERVER_URL=redhat-kong-gitops-server-openshift-gitops.apps.kongcp.kni.syseng.devcluster.openshift.com
oc get secret -n openshift-gitops redhat-kong-gitops-cluster -ojsonpath='{.data.admin\.password}' | base64 -d
```




