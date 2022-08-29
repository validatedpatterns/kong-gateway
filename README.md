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
Error from server (NotFound): namespaces "openshift-gitops" not found
sleep 5 seconds until openshift-gitops namespace is created.
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

Now wait until Vault and ArgoCD are properly deployed. Note that the Vault pods will be `Running` but not `Ready`. We need to initialize them.

### Initialize the hasicorp vault

The Vault initialization happens through Ansible Playbooks placed in the [common](./common) folder.

Requirements

* ansible 2.13 or greater
* jmespath

#### Run the playbook

First make sure that the kong `license.json` file is placed in the base folder.

```bash
$ cd common
$ make vault-init
...
PLAY RECAP *************************************************************************************************************************************************
localhost                  : ok=15   changed=9    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

#### Optional: Vault initialization confirmations

* Check the vault cluster is ready

```bash
↳ oc get po -n vault
NAME                                    READY   STATUS    RESTARTS   AGE
vault-0                                 1/1     Running   0          149m
vault-1                                 1/1     Running   0          149m
vault-agent-injector-74c848f67b-tlw7f   1/1     Running   0          149m
```

* Login to the vault-0 pod (leader)

```bash
$ oc exec -n vault vault-0 -- vault login $(cat common/pattern-vault.init | jq -r ".root_token")
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                hvs.zLLu2mGooaX7bY4dqLadMe4G
token_accessor       4VkVHfvlXfgIAdCKjnv4aRxn
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```

* Check the vault is unsealed

```bash
$ oc exec -n vault vault-0 -- vault status
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
```

* Confirm followers and the leader are healthy

```bash
$ oc exec -n vault vault-0 -- vault operator raft list-peers  
Node                                    Address                        State       Voter
----                                    -------                        -----       -----
f923f308-7748-c36a-1ded-1b2d468aad5e    vault-0.vault-internal:8201    leader      true
fa068454-5e74-c554-daf1-98f62663d373    vault-1.vault-internal:8201    follower    true
```

* Check the secret with the license exists

```bash
↳ oc exec -n vault vault-0 -- vault kv get secret/kubernetes
===== Secret Path =====
secret/data/kubernetes

======= Metadata =======
Key                Value
---                -----
created_time       2022-08-23T11:18:08.624777327Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

===== Data =====
Key        Value
---        -----
license    {"license":{"****"}}
```

* Validate the policy

```bash
$ oc exec -n vault vault-0 -- vault policy read argocd-repo-server
path "secret/data/kubernetes/*" { capabilities = ["read"] }
```

* Validate the auth and the role

```bash
$ oc exec -n vault vault-0 -- vault auth list
Path           Type          Accessor                    Description
----           ----          --------                    -----------
kubernetes/    kubernetes    auth_kubernetes_ab19d021    n/a

$ oc exec -n vault vault-0 -- vault read auth/kubernetes/role/argocd-repo-server
Key                                 Value
---                                 -----
alias_name_source                   serviceaccount_uid
bound_service_account_names         [argocd-repo-server]
bound_service_account_namespaces    [openshift-gitops]
policies                            [argocd-repo-server default]
token_bound_cidrs                   []
token_explicit_max_ttl              0s
token_max_ttl                       0s
token_no_default_policy             false
token_num_uses                      0
token_period                        0s
token_policies                      [argocd-repo-server default]
token_ttl                           15m
token_type                          default
ttl                                 15m
```

* Validate the ArgoCD - Vault integration works

```bash
$ REPO_SVR_POD=$(oc get po -l app.kubernetes.io/name=redhat-kong-gitops-repo-server -ojson | jq -r '.items[0].metadata.name')
$ oc cp gateway/prereqs/base/vault/license-sercret.yaml ${REPO_SVR_POD}:secret.yaml
$ oc exec $REPO_SVR_POD -- argocd-vault-plugin generate secret.yaml
apiVersion: v1
kind: Secret
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
    avp.kubernetes.io/path: secret/data/kubernetes
  name: kong-enterprise-license
  namespace: kong
stringData:
  license: '{"license":{...}}'
type: Opaque
---
```

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
        - [X] Automation for Setup, initialize and unsealing of vault.
        - [X] Automated script for project.yaml
        - [] Application Set for vault
        - [] Can you rationlize cp and dp further? 