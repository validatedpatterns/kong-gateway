# Start Here

If you've followed a link to this repository, but are not really sure what it contains
or how to use it, head over to [Multicloud GitOps](http://hybrid-cloud-patterns.io/multicloud-gitops/)
for additional context and installation instructions

## Create the secrets file

When configuring vault there is a `values-secret.yaml` file that `push_secrets` Ansible playbook will use.
For Kong we will create a key-value for the license as follows:

```bash
cat << EOF >> values-secret.yaml 
secrets:
  kong:
    license: "$(sed 's/\"//g' license.json)"
EOF
```

## Get the tokens and certs of the external clusters

Use these variables to create an entry for your cluster in the `values-secret.yaml` file using the following code:

```bash
CLUSTER_NAME=example
CLUSTER_API_URL=https://api.mycluster.jqic.p1.openshiftapps.com:6443
oc login $CLUSTER_API_URL
oc create sa argocd-external -n default
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:default:argocd-external
CLUSTER_TOKEN=$(oc describe secret -n default argocd-external-token | grep 'token:' | awk '{print$2}')
oc extract -n openshift-config cm/kube-root-ca.crt --to=- --keys=ca.crt > ${CLUSTER_NAME}.crt
```

Use the previous environment variables to create an entry for your cluster in the `values-secret.yaml` file using the following code:

```bash
cat << EOF >> values-secret.yaml 
  cluster_${CLUSTER_NAME}:
    server: ${CLUSTER_API_URL}
    bearerToken: ${CLUSTER_TOKEN}
files:
  cluster_${CLUSTER_NAME}_ca: `pwd`/${CLUSTER_NAME}.crt
EOF
```

### Adding more clusters

Repeat the script to create the `sa` and extract the token and root CA into a file. Now
add the cluster secrets and ca files like this to keep the sections:

```bash
sed -i "/files:/i\  cluster_${CLUSTER_NAME}:\n    server: ${CLUSTER_API_URL}\n    bearerToken: ${CLUSTER_TOKEN}" values-secret.yaml
echo "  cluster_${CLUSTER_NAME}_ca: `pwd`/${CLUSTER_NAME}.crt" >> values-secret.yaml
```

## Copy the secrets to your home

Copy the `values-secret.yaml` to your `$HOME` directory

```bash
cp values-secret.yaml ~/values-secret.yaml
```

## Install the main Helm chart

```bash
make install
```

**Note**: Sometimes the main ArgoCD app needs a manual refresh to start progressing.

## Uninstall

```bash
make uninstall
```
