# Architecture

## Diagrams

[TODO] - Mriganka

## Logical Repositories

  [Kong - maintained by kong operator](./gateway/)

  [Gitops - maintained by gitops operator](./openshift-gitops/)

  [Demo Application - Maintained by gitops operator](./kong-demo-app/)

## Configuration

  [Kong control plane - maintained by kong operator](./gateway/controlplane/values.yaml)

  [Kong data plane - maintained by kong operator](./gateway/dataplane/values.yaml)

  [Software Infrastructure - maintained by kong operator](./gateway/prereqs/operators/values.yaml)

  [Giptops - maintained by gitops operator](./openshift-gitops/apps/charts/values.yaml)

## Implementation

### Set up the infra

#### Install the operator

```bash
$ ./scripts/infra/argocd.sh provision
subscription.operators.coreos.com/openshift-gitops-operator created
sleep 10 seconds until argocd subscription is installed.
Operator subscription installed successfully
Deploy ArgoCD app
serviceaccount/argocd-repo-server created
argocd.argoproj.io/redhat-kong-gitops created
sleep 10 seconds until argocd app is Available.
ArgoCD app deployed successfully
```

#### Get the route and password of argocd gui

```bash
oc get routes -n openshift-gitops redhat-kong-gitops-server --template='{{ .spec.host }}'
```

```bash
oc get secret -n openshift-gitops redhat-kong-gitops-cluster -ojsonpath='{.data.admin\.password}' | base64 -d
```

#### Add controlplane and dataplane clusters

```bash
oc get secret -n openshift-gitops redhat-kong-gitops-cluster -ojsonpath='{.data.admin\.password}' | base64 -d
argocd login `oc get routes -n openshift-gitops redhat-kong-gitops-server --template='{{.spec.host}}'`
argocd cluster add -y --name dp <dp-context>
argocd cluster add -y --name cp <cp-context>
```

#### Create the project for control plane and data plane

##### Use defaults

```bash
kustomize build openshift-gitops/infra/base | kubectl apply -f -
```

##### Use a custom repository / branch

Copy the `repositories.yaml.template` file in [./openshift-gitops/infra/overlays](./openshift-gitops/infra/overlays) to `repositories.yaml` and edit the values if you need
to update the repository path or branch where the charts will be installed from.

```bash
kustomize build openshift-gitops/infra/overlays | kubectl apply -f -
```

### Install the hasicorp vault
[TODO] - Ruben
  - Create a argo app to deploy vault and store the secrets(license-secret)
Refer [Vault setup](/openshift-gitops/infra/vault/evault.md) for basic dev setup of vault

## Deploy kong

### Deploy kong and bookinfo app

```bash
oc apply -f openshift-gitops/app.yaml
```

### Validate deployment

Check the admin endpoint is available
```bash
kubectx cp
http `oc get route -n kong kong-kong-admin --template='{{.spec.host}}'` | jq .version
```
Output
```
"2.8.1.1-enterprise-edition"
```

Check the cluster-urls
```bash
kubectx cp
oc get cm cluster-urls -n kong -oyaml
```
Output
```
apiVersion: v1
data:
  CLUSTER_TELEMETRY_URL: aada71fce488d417b9db340ce87c9b4b-763449203.us-west-1.elb.amazonaws.com
  CLUSTER_URL: aff89d1140e6b41299f85bd663592c20-1822993472.us-west-1.elb.amazonaws.com
kind: ConfigMap
metadata:
  creationTimestamp: "2022-07-02T12:00:54Z"
  name: cluster-urls
  namespace: kong
  resourceVersion: "4008563"
  uid: 309e0540-e8e9-470a-b795-b00816206273
```

Check the logs of patch deploy job
```bash
kubectx cp
oc logs -n kong -l job-name=patch-deploy
```
Output
```
redhat-kong-gitops-server-openshift-gitops.apps.cwylie-us-west-1b.kni.syseng.devcluster.openshift.com
Be4OqiXClFN7paoWDIAPZj1tUnfsK06J
'admin:login' logged in successfully
Context 'redhat-kong-gitops-server-openshift-gitops.apps.cwylie-us-west-1b.kni.syseng.devcluster.openshift.com' updated
time="2022-07-02T12:47:20Z" level=info msg="Resource 'kong-kong' patched"
```

Check clustering
```bash
kubectx cp
http `oc get route -n kong kong-kong-admin --template='{{ .spec.host }}'`/clustering/status
```

Check proxy
```bash
kubectx dp
http `oc get route -n kong kong-kong-proxy --template='{{ .spec.host }}'`/
```
Check grafana dashboard
```bash
kubectx dp
echo $(oc get secret -n kong --context dp grafana-admin-credentials -ojsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d)
```

### Validate overall deployment
```bash
kubectx cp
export KONG_ADMIN_URL=$(oc get route kong-kong-admin -o jsonpath='{.spec.host}' -n kong)
kubectx dp
export KONG_DP_PROXY_URL=$(oc get route kong-kong-proxy -o jsonpath='{.spec.host}' -n kong)
http $KONG_DP_PROXY_URL
kubectx cp
http $KONG_ADMIN_URL/services name=bookinfosvc url='http://productpage.bookinfo.svc.cluster.local:9080' 
http $KONG_ADMIN_URL/services/bookinfosvc/routes name='bookinforoute' paths:='["/bookinfo"]' kong-admin-token:kong
http $KONG_DP_PROXY_URL/bookinfo/productpage
```

# Customer demo use cases
### Validate Ingress
```bash
kubectx dp
export KONG_DP_PROXY_URL=$(oc get route kong-kong-proxy -o jsonpath='{.spec.host}' -n kong)
kubectx cp

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: bookinfo-svc
  namespace: default
spec:
  type: ExternalName
  externalName: a01ac35c08fd34afc9b0581d627c86a8-1293833235.ca-central-1.elb.amazonaws.com
EOF

cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bookinfo
  namespace: default
  annotations:
    konghq.com/strip-path: "true"
    kubernetes.io/ingress.class: kong
spec:
  rules:
  - http:
      paths:
        - path: /bookinfo-ingress
          pathType: Prefix
          backend:
            service:
              name: bookinfo-svc
              port:
                number: 9080
EOF
```
```bash
http $KONG_DP_PROXY_URL/bookinfo-ingress/productpage
```

### keycloak validation
```bash
kubectx dp
KEYCLOAK_URL=$(oc get routes -n keycloak keycloak --template={{.spec.host}})

[Example]
https://keycloak-keycloak.apps.dp.kni.syseng.devcluster.openshift.com/auth/admin/master/console/ #/realms/kong
```

Extract the username/password:

```bash
kubectl get secret -n keycloak credential-kong-keycloak -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'

```

You can validate the access_token retrieved from keycloak by doing the following:

```bash
http --verify=no -f https://`oc get routes -n keycloak keycloak --template={{.spec.host}}`/auth/realms/kong/protocol/openid-connect/token client_id=kong-demo-client grant_type=password username=kermit password=kong client_secret=client-secret | jq -r .access_token
```

Apply the kong plugin for keycloak
```bash
kubectx cp

cat <<EOF | oc apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: keycloak-auth-plugin
config: 
  auth_methods:
  - authorization_code
  - session
  hide_credentials: true
  issuer: https://keycloak-keycloak.apps.dp.kni.syseng.devcluster.openshift.com/auth/realms/kong
  client_id:
  - kong-demo-client
  client_secret:
  - client-secret
  roles_required:
  - customer
plugin: openid-connect
EOF
```

Annotate the service with keycloak plugin
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: bookinfo-svc
  namespace: default
  annotations:
    konghq.com/plugins: keycloak-auth-plugin
spec:
  type: ExternalName
  externalName: a01ac35c08fd34afc9b0581d627c86a8-1293833235.ca-central-1.elb.amazonaws.com
EOF
```


Validate
```
[Example]

http://kong-kong-proxy-kong.apps.dp.kni.syseng.devcluster.openshift.com/bookinfo-ingress/productpage
```

### Validate monitoring

Update the service for prometheus plugin
```bash
kubectx cp

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: bookinfo-svc
  namespace: default
  annotations:
    konghq.com/plugins: prometheus-plugin
spec:
  type: ExternalName
  externalName: a01ac35c08fd34afc9b0581d627c86a8-1293833235.ca-central-1.elb.amazonaws.com
EOF
```
Apply the kong plugin to generate metrics

```bash
kubectx cp

cat <<EOF | oc apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongClusterPlugin
metadata:
  name: prometheus-plugin
  annotations:
    kubernetes.io/ingress.class: kong
  labels:
    global: "true"
config:
  per_consumer: true
plugin: prometheus
EOF
```

Generate metrics data

```bash
while [ 1 ]; do curl $KONG_DP_PROXY_URL/bookinfo-ingress/productpage; echo; done
```

## Clean up

### Uninstall the ArgoCD projects and applications

#### Uninstall using defaults

```bash
kustomize build openshift-gitops/infra/base | kubectl delete -f -
```

#### Uninstall using a custom repository / branch

If you used the `repositories.yaml` file, use the overlays instead.

```bash
kustomize build openshift-gitops/infra/overlays | kubectl delete -f -
```

### Uninstall ArgoCD

```bash
./scripts/infra/argocd.sh delete
```

- TODO
    - Iteration 1
        - [X] PostInstall for CP
        - [X] Data Plane
        - [X] kustomize
        - [X] Monitoring in data plane
        - [X] Authentication and Authorization
        - [X] Bookinfo app
        - [X] app of apps
        - [X] Enterprise Vault - Retrieving secrets from the vault
    - Iteration 2
        - [] Automation for Setup, initialize and unsealing of vault.
        - [] Same name of apps in different projects
        - [] Automated script for project.yaml
        - [] Application Set for vault
        - [] Can you rationlize cp and dp further? 