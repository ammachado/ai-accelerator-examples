#!/bin/bash
set -e

# check login
check_oc_login() {
    oc cluster-info | head -n1
    oc whoami || exit 1
    echo
}

# Function to check for required command-line tools
check_commands() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: ${cmd} is not installed. Please install it to continue."
            exit 1
        fi
    done
}


# Function to wait for an OpenShift resource
# Usage: wait_for_oc_resource <resource_type> <resource_name> <namespace> <condition> <timeout_seconds>
wait_for_oc_resource() {
    # Assign arguments to local variables for clarity and better scope
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local condition="$4"
    local timeout_seconds="${5:-5m}" # Default to 5 minutes

    if [ -z "$resource_type" ] || [ -z "$resource_name" ] || [ -z "$namespace" ] || [ -z "$condition" ]; then
        echo "Error: Missing required arguments for wait_for_oc_resource." >&2
        echo "Usage: wait_for_oc_resource <resource_type> <resource_name> <namespace> <condition> [<timeout_seconds>]" >&2
        return 1 # Indicate failure
    fi

    # --- Wait for the Namespace to be Active ---
    echo "Waiting for namespace '$namespace' to be Active..."
    until oc wait --for=jsonpath='{.status.phase}'=Active namespace/"$namespace" --timeout="$timeout_seconds"
    do
        echo "Namespace '$namespace' not yet Active. Retrying in 5 seconds..." >&2
        sleep 5
    done
    echo "Namespace '$namespace' is now Active."


    echo "Waiting for $resource_type/$resource_name in namespace $namespace to to meet condition '$condition'..."
    until oc wait --for="$condition" "$resource_type"/"$resource_name" -n "$namespace" --timeout="$timeout_seconds"
    do
        echo "Resource haven't met '$condition' yet. Retrying in 5 seconds..." >&2 # Direct retry messages to stderr
        sleep 5
    done

    if [ $? -eq 0 ]; then
        echo "$resource_type/$resource_name is now $condition!"
        return 0 # Indicate success
    else
        echo "Error: Failed to wait for $resource_type/$resource_name to meet condition '$condition'." >&2
        return 1 # Indicate failure
    fi
}