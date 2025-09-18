#!/usr/bin/env bash

LABEL_SELECTOR="rhoai-example=maas-3scale"

# ApplicationSet
echo "Deleting ArgoCD resources..."
oc get applicationset -n openshift-gitops -l "$LABEL_SELECTOR" -o name | xargs oc delete -n --wait=false -n openshift-gitops
oc get apps -n openshift-gitops -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n openshift-gitops --type=merge
oc get apps -n openshift-gitops -l "$LABEL_SELECTOR" -o name | xargs oc delete -n --wait=false -n openshift-gitops
oc get appproject -n openshift-gitops -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n openshift-gitops --type=merge
oc get appproject -n openshift-gitops -l "$LABEL_SELECTOR" -o name | xargs oc delete -n --wait=false -n openshift-gitops

# 3scale
if oc get namespace 3scale &>/dev/null; then
    echo "Deleting 3scale resources..."
    oc get applicationauth -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get application.capabilities.3scale.net -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get developeraccount -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get developeruser -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get activedoc -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get proxyconfigpromote -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get product -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get backend -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get apimanager -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get custompolicydefinition -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc wait --for=delete apimanager/apimanager --timeout=60s

    oc get subscription -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    #oc get tektonresult -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get pipelinerun -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get taskrun -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get tasks -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale
    oc get eventlistener -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    # Delete any running pod from jobs
    for job in $(oc get job -n 3scale -l "$LABEL_SELECTOR" -o name | cut -d '/' -f 2); do
        oc get pod -l "batch.kubernetes.io/job-name=$job" -n 3scale -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
        oc get pod -l "batch.kubernetes.io/job-name=$job" -n 3scale -o name | xargs oc delete -n 3scale
    done

    oc get job -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
    oc get job -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    oc get rolebindings -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
    oc get rolebindings -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    oc get serviceaccount -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
    oc get serviceaccount -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    oc get secret -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
    oc get secret -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    oc get configmap -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc patch -p '{"metadata":{"finalizers":[]}}' -n 3scale --type=merge
    oc get configmap -n 3scale -l "$LABEL_SELECTOR" -o name | xargs oc delete -n 3scale

    oc delete namespace 3scale || true
fi

# Keycloak
if oc get namespace rhbk &>/dev/null; then
    echo "Deleting rhbk resources..."
    oc get keycloak -n rhbk -l "$LABEL_SELECTOR" -o name | xargs oc delete -n rhbk --wait=false
    oc get statefulset -n rhbk -l "$LABEL_SELECTOR" -o name | xargs oc delete -n rhbk --wait=false
    oc get subscription -n rhbk -l "$LABEL_SELECTOR" -o name | xargs oc delete -n rhbk
    oc delete namespace rhbk || true
fi

# Minio
if oc get namespace minio &>/dev/null; then
    echo "Deleting minio resources..."
    oc get deployment -n minio -l "$LABEL_SELECTOR" -o name | xargs oc delete -n minio --wait=false
    oc delete namespace minio || true
fi

# LLM
if oc get namespace llm-hosting &>/dev/null; then
    echo "Deleting llm-hosting resources..."
    oc get servingruntime -n llm-hosting -l "$LABEL_SELECTOR" -o name | xargs oc delete -n llm-hosting --wait=false
    oc get inferenceservice -n llm-hosting -l "$LABEL_SELECTOR" -o name | xargs oc delete -n llm-hosting --wait=false
    oc delete namespace llm-hosting || true
fi

# Shared secrets
if oc get namespace maas-3scale-shared-secrets &>/dev/null; then
    echo "Deleting maas-3scale-shared-secrets resources..."
    oc get clusterexternalsecret -l "$LABEL_SELECTOR" -o name | xargs oc delete --wait=false
    oc get clustersecretstore -l "$LABEL_SELECTOR" -o name | xargs oc delete --wait=false
    oc get externalsecret -n maas-3scale-shared-secrets -l "$LABEL_SELECTOR" -o name | xargs oc delete -n maas-3scale-shared-secrets --wait=false
    oc get clustersecretprovider -l "$LABEL_SELECTOR" -o name | xargs oc delete --wait=false
    oc get secretstore -n maas-3scale-shared-secrets -l "$LABEL_SELECTOR" -o name | xargs oc delete -n maas-3scale-shared-secrets --wait=false
    oc get serviceaccount -n maas-3scale-shared-secrets -l "$LABEL_SELECTOR" -o name | xargs oc delete -n maas-3scale-shared-secrets --wait=false
    oc get secret -n maas-3scale-shared-secrets -l "$LABEL_SELECTOR" -o name | xargs oc delete -n maas-3scale-shared-secrets --wait=false
    oc get configmap -n maas-3scale-shared-secrets -l "$LABEL_SELECTOR" -o name | xargs oc delete -n maas-3scale-shared-secrets --wait=false
    oc delete namespace maas-3scale-shared-secrets || true
fi

if oc get sub -l "$LABEL_SELECTOR" -n external-secrets-operator &>/dev/null; then
    echo "Deleting remaining operator subscriptions..."
    oc get sub -l "$LABEL_SELECTOR" -o name -n external-secrets-operator | xargs oc delete -n external-secrets-operator
fi

# Helm release information
oc get secret -n openshift-gitops -l name=models-as-a-service-3scale -l owner=helm -l "$LABEL_SELECTOR" -o name | xargs oc delete -n openshift-gitops || true
