#!/bin/bash
set -euo pipefail

# Color helpers for console output (pink and reset)
if [ -t 1 ]; then
    COLOR_PINK="$(printf '\033[95m')"
    COLOR_RESET="$(printf '\033[0m')"
else
    COLOR_PINK=""
    COLOR_RESET=""
fi

# This script contains prerequisite and post-install steps for the
# Models as a Service example.

# Function to check for required command-line tools
check_commands() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: ${cmd} is not installed. Please install it to continue."
            exit 1
        fi
    done
}

prerequisite() {
    echo "--- Running prerequisite steps for Models as a Service ---"

    check_commands jq yq oc git

    # 3scale RWX Storage check
    echo "The 3scale operator requires a storage class with ReadWriteMany (RWX) access mode."
    echo "Red Hat OpenShift Data Foundation (ODF) is the recommended way to provide this."
    read -p "Do you have an RWX-capable storage class available in your cluster? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "An RWX storage class is required. Please install OpenShift Data Foundation (ODF) or another RWX-capable storage solution and then re-run the script."
        exit 1
    fi

    # Update wildcard domain
    echo "Discovering cluster wildcard domain..."
    local WILDCARD_DOMAIN_APPS=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
    if [ -z "$WILDCARD_DOMAIN_APPS" ]; then
        echo "Could not automatically determine wildcard domain."
        exit 1
    else
        echo "Found wildcard domain: ${WILDCARD_DOMAIN_APPS}"
    fi


    # TODO: this secret is required by 3scale; here, for testing purposes, I'm copying one from the cluster

    # Create namespace if it doesn't exist
    if ! oc get namespace 3scale &>/dev/null; then
        echo "Creating namespace 3scale..."
        oc create namespace 3scale && \
            oc label namespace 3scale argocd.argoproj.io/managed-by=openshift-gitops
    fi

    # Create secret only if it doesn't exist
    if ! oc get secret threescale-registry-auth -n 3scale &>/dev/null; then
        echo "Creating threescale-registry-auth secret..."
        oc extract secret/pull-secret -n openshift-config --keys=.dockerconfigjson --to=- \
            | grep -v .dockerconfigjson \
            | oc create secret generic threescale-registry-auth -n 3scale --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=/dev/stdin
    else
        echo "Secret threescale-registry-auth already exists in 3scale namespace."
    fi


    # Save substitutions for later usage
    subs+=(
        "WILDCARD_DOMAIN=${WILDCARD_DOMAIN_APPS}"
    )

    echo "--- Prerequisite steps completed. ---"
}

post-install-steps() {
    echo "--- Running post-install steps for Models as a Service ---"

    # Define common curl options.
    # WARNING: Using -k to disable certificate validation is a security risk.
    # This should only be used in trusted, controlled development environments.
    # In production, you should ensure proper certificates are configured.
    CURL_OPTS=("-s" "-k")

    # Wait for 3scale namespace to be created
    echo "Waiting for the 3scale namespace to be created..."
    until oc get namespace 3scale &> /dev/null; do
        echo "Namespace '3scale' not found. Waiting..."
        sleep 10
    done
    echo "Namespace '3scale' found."
    
    # Wait for 3scale APIManager to be created
    echo "Waiting for 3scale APIManager to be created..."
    until oc get apimanager/apimanager -n 3scale &> /dev/null; do
        echo "APIManager 'apimanager' in namespace '3scale' not found. Waiting..."
        sleep 30
    done
    echo "APIManager 'apimanager' in namespace '3scale' found."

    # Wait for 3scale to be ready
    echo "Waiting for 3scale APIManager to be ready..."
    oc wait --for=condition=Available --timeout=15m apimanager/apimanager -n 3scale

    # Get 3scale admin password
    THREESCALE_ADMIN_PASS=$(oc get secret system-seed -n 3scale -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d)
    THREESCALE_ADMIN_URL=$(oc get route -l zync.3scale.net/route-to=system-provider -n 3scale -o jsonpath='{.items[0].spec.host}')
    echo "3scale Admin URL: ${COLOR_PINK}https://${THREESCALE_ADMIN_URL}${COLOR_RESET}"
    echo "3scale Admin Password: ${COLOR_PINK}${THREESCALE_ADMIN_PASS}${COLOR_RESET}"


    # Wait for redhat-sso namespace to be created
    echo "Waiting for the redhat-sso namespace to be created..."
    until oc get namespace redhat-sso &> /dev/null; do
        echo "Namespace 'redhat-sso' not found. Waiting..."
        sleep 10
    done
    echo "Namespace 'redhat-sso' found."

    # Wait for REDHAT-SSO Keycloak to be created
    echo "Waiting for statefulset Keycloak to be created..."
    until oc get statefulset/keycloak -n redhat-sso &> /dev/null; do
        echo "statefulset 'keycloak' in namespace 'redhat-sso' not found. Waiting..."
        sleep 30
    done
    echo "statefulset 'keycloak' in namespace 'redhat-sso' found."

    # Get REDHAT-SSO credentials
    echo "Waiting for statefulset 'keycloak' to be ready..."
    oc wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/keycloak -n redhat-sso --timeout=15m
    
    REDHATSSO_ADMIN_USER=$(oc get secret credential-redhat-sso -n redhat-sso -o jsonpath='{.data.ADMIN_USERNAME}' | base64 -d)
    REDHATSSO_ADMIN_PASS=$(oc get secret credential-redhat-sso -n redhat-sso -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 -d)
    REDHATSSO_URL=$(oc get route keycloak -n redhat-sso -o jsonpath='{.spec.host}')
    echo "REDHAT-SSO Admin URL: ${COLOR_PINK}https://${REDHATSSO_URL}${COLOR_RESET}"
    echo "REDHAT-SSO Admin User: ${COLOR_PINK}${REDHATSSO_ADMIN_USER}${COLOR_RESET}"
    echo "REDHAT-SSO Admin Password: ${COLOR_PINK}${REDHATSSO_ADMIN_PASS}${COLOR_RESET}"

    echo "Retrieving 3scale admin access token and host..."
    ACCESS_TOKEN=$(oc get secret system-seed -n 3scale -o jsonpath='{.data.ADMIN_ACCESS_TOKEN}' | base64 -d)
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "Failed to retrieve 3scale access token. Please ensure the 'system-seed' secret exists in the '3scale' namespace and is populated."
        return 1
    fi

    ADMIN_HOST=$(oc get route -n 3scale | grep 'maas-admin' | awk '{print $2}')
    if [ -z "$ADMIN_HOST" ]; then
        echo "Failed to retrieve 3scale admin host. Please ensure the route exists in the '3scale' namespace."
        return 1
    fi
    echo "Found 3scale admin host: ${ADMIN_HOST}"

    configure_sso_developer_portal

    echo "--- Post-install steps completed! ---"
    
    show_developer_portal_info

    # Clean up the temp file if it exists
    rm -f -- "${RESPONSE_FILE-}"
}

show_developer_portal_info() {
    echo "--- Developer Portal Information ---"
    
    # Print Developer Portal route (system-developer)
    DEVELOPER_PORTAL_HOST=$(oc get route -n 3scale -l 'zync.3scale.net/route-to=system-developer' -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
    if [ -n "${DEVELOPER_PORTAL_HOST}" ]; then
        echo "Developer Portal URL: ${COLOR_PINK}https://${DEVELOPER_PORTAL_HOST}${COLOR_RESET}"
    else
        echo "Developer Portal route not found in namespace '3scale'."
    fi

    # Try to read credentials from secret in 3scale namespace
    if oc get secret developer-login-cred -n 3scale >/dev/null 2>&1; then
        EXISTING_USER=$(oc get secret developer-login-cred -n 3scale -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || true)
        EXISTING_PASS=$(oc get secret developer-login-cred -n 3scale -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)
        if [ -n "${EXISTING_USER}" ] && [ -n "${EXISTING_PASS}" ]; then
            echo "Developer User Credentials:"
            echo "Username: ${COLOR_PINK}${EXISTING_USER}${COLOR_RESET}"
            echo "Password: ${COLOR_PINK}${EXISTING_PASS}${COLOR_RESET}"
        else
            echo "Secret 'developer-login-cred' found but missing fields."
            echo "Developer user will be created by the operator-managed YAML manifests."
        fi
    else
        echo "Secret 'developer-login-cred' not found in namespace '3scale'."
        echo "Developer user will be created by the operator-managed YAML manifests."
    fi
}

configure_sso_developer_portal() {
    echo "--- Configuring 3scale Developer Portal SSO ---"

    RESPONSE_FILE=$(mktemp)
    trap 'rm -f -- "$RESPONSE_FILE"' EXIT

    local HTTP_CODE
    HTTP_CODE=$(curl "${CURL_OPTS[@]}" -w "%{http_code}" -o "${RESPONSE_FILE}" "https://${ADMIN_HOST}/admin/api/authentication_providers.xml?access_token=${ACCESS_TOKEN}")

    if [[ "$HTTP_CODE" -ge 400 ]]; then
        echo "Error: Failed to get Authentication Providers. Received HTTP status ${HTTP_CODE}."
        echo "Response from server:"
        cat "${RESPONSE_FILE}"
        return 1
    fi

    # Disable Developer Portal access code (make portal publicly accessible)
    echo "Disabling Developer Portal access code..."
    HTTP_CODE=$(curl "${CURL_OPTS[@]}" -w "%{http_code}" -o "${RESPONSE_FILE}" \
        -X PUT "https://${ADMIN_HOST}/admin/api/provider.xml" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "access_token=${ACCESS_TOKEN}" \
        -d "site_access_code=")
    if [[ "$HTTP_CODE" -ge 400 ]]; then
        echo "Error: Failed to clear Developer Portal access code. HTTP ${HTTP_CODE}."
        echo "Response from server:"
        cat "${RESPONSE_FILE}"
        return 1
    else
        echo "Developer Portal access code removed."
    fi

    # Re-fetch authentication providers after account update
    HTTP_CODE=$(curl "${CURL_OPTS[@]}" -w "%{http_code}" -o "${RESPONSE_FILE}" "https://${ADMIN_HOST}/admin/api/authentication_providers.xml?access_token=${ACCESS_TOKEN}")
    if [[ "$HTTP_CODE" -ge 400 ]]; then
        echo "Error: Failed to refresh Authentication Providers. HTTP ${HTTP_CODE}."
        echo "Response from server:"
        cat "${RESPONSE_FILE}"
        return 1
    fi

    local SSO_INTEGRATION_EXISTS
    SSO_INTEGRATION_EXISTS=$(cat "${RESPONSE_FILE}" | yq -p xml -o json | jq -r '[.authentication_providers.authentication_provider?] | flatten | .[] | select(.kind? == "keycloak") | .id')

    if [ -n "$SSO_INTEGRATION_EXISTS" ]; then
        echo "RH-SSO integration already exists. Skipping creation."
    else
        echo "Creating RH-SSO integration..."
        local CLIENT_SECRET
        # Get client secret from the Kubernetes secret created by the Keycloak operator
        echo "Retrieving client secret from Kubernetes secret..."
        CLIENT_SECRET=$(oc get secret keycloak-client-secret-3scale-client -n redhat-sso -o jsonpath='{.data.CLIENT_SECRET}' 2>/dev/null | base64 -d || true)
        if [ -z "$CLIENT_SECRET" ]; then
            echo "Error: CLIENT_SECRET not found in Kubernetes secret. Ensure the KeycloakClient CR has been created and processed by the operator."
            return 1
        fi
        HTTP_CODE=$(curl "${CURL_OPTS[@]}" -w "%{http_code}" -o "${RESPONSE_FILE}" \
            -X POST "https://${ADMIN_HOST}/admin/api/authentication_providers.xml?access_token=${ACCESS_TOKEN}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "kind=keycloak" \
            -d "name=Red Hat Single Sign-On" \
            -d "client_id=3scale" \
            -d "client_secret=${CLIENT_SECRET}" \
            -d "site=https://${REDHATSSO_URL}/auth/realms/maas" \
            -d "published=true")
        
        if [[ "$HTTP_CODE" -ge 400 ]]; then
            echo "Error: Failed to create RH-SSO integration. Received HTTP status ${HTTP_CODE}."
            echo "Response from server:"
            cat "${RESPONSE_FILE}"
            return 1
        fi
        echo "RH-SSO integration created."
    fi

    local AUTH_PROVIDER_ID
    AUTH_PROVIDER_ID=$(curl "${CURL_OPTS[@]}" -X GET "https://${ADMIN_HOST}/admin/api/authentication_providers.xml?access_token=${ACCESS_TOKEN}" | yq -p xml -o json | jq -r '[.authentication_providers.authentication_provider?] | flatten | .[] | select(.kind? == "keycloak") | .id')
    
    if [ -z "$AUTH_PROVIDER_ID" ]; then
        echo "Failed to retrieve Authentication Provider ID. Cannot update 'Always approve accounts'."
        return 1
    fi

    echo "Updating RH-SSO integration to always approve accounts..."
    HTTP_CODE=$(curl "${CURL_OPTS[@]}" -w "%{http_code}" -o "${RESPONSE_FILE}" \
        -X PUT "https://${ADMIN_HOST}/admin/api/authentication_providers/${AUTH_PROVIDER_ID}.xml?access_token=${ACCESS_TOKEN}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "automatically_approve_accounts=true")

    if [[ "$HTTP_CODE" -ge 400 ]]; then
        echo "Error: Failed to update RH-SSO integration. Received HTTP status ${HTTP_CODE}."
        echo "Response from server:"
        cat "${RESPONSE_FILE}"
        return 1
    fi
    echo "RH-SSO integration updated."

    echo "--- 3scale Developer Portal SSO configuration completed. ---"
}
