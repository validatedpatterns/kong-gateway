#!/bin/sh


GITOPS_SUBSCRIPTION='openshift-gitops/operators/gitops-operator.yaml'
ARGOCD_APP='openshift-gitops/operators/argocd.yaml'

function get_subscription_status {
  status=$(kubectl get subscription --ignore-not-found=true -n openshift-operators openshift-gitops-operator --template='{{.status.state}}')
  echo ${status:-Unknown}
}

function get_app_status {
  status=$(kubectl get argocd --ignore-not-found=true -n openshift-gitops redhat-kong-gitops --template='{{.status.phase}}')
  echo ${status:-Unknown}
}

if [ "$1" = "provision" ]; then
  kubectl apply --wait -f $GITOPS_SUBSCRIPTION
  status=$(get_subscription_status)
  until [[ ${status} == 'AtLatestKnown' ]]; do
    echo sleep 10 seconds until argocd subscription is installed.
    sleep 10s
    status=$(get_subscription_status)
  done
  echo Operator subscription installed successfully
  echo Deploy ArgoCD app
  kubectl apply --wait -f $ARGOCD_APP
  status=$(get_app_status)
  until [[ ${status} == 'Available' ]]; do
    echo sleep 10 seconds until argocd app is Available.
    sleep 10s
    status=$(get_app_status)
  done
  echo ArgoCD app deployed successfully
elif [[ "$1" = "delete" ]]; then
  kubectl delete --ignore-not-found=true -f $ARGOCD_APP
  currentCSV=$(kubectl get subscriptions --ignore-not-found=true -n openshift-operators openshift-gitops-operator --template='{{.status.currentCSV}}')
  kubectl delete  --ignore-not-found=true -f $GITOPS_SUBSCRIPTION
  if [[ -n $currentCSV ]]; then
    kubectl delete clusterserviceversion -n openshift-operators $currentCSV
  fi
else
  echo "unexpected argument, expected 'provision' or 'delete', got $1"
fi
