#!/bin/bash
set -e

EXAMPLES_DIR="examples"
ARGOCD_NS="openshift-gitops"

source "$(dirname "$0")/functions.sh"

choose_example() {
    examples_dir=${EXAMPLES_DIR}

    echo
    echo "Choose an example you wish to deploy?"
    PS3="Please enter a number to select an example folder: "

    select chosen_example in $(basename -a ${examples_dir}/*/); 
    do
    test -n "${chosen_example}" && break;
    echo ">>> Invalid Selection";
    done

    echo "You selected ${chosen_example}"
 
    CHOSEN_EXAMPLE_PATH=${examples_dir}/${chosen_example}
}

choose_example_option() {
    if [ -z "$1" ]; then
        echo "Error: No option provided to choose_example_option()"
        echo "Usage: choose_example_option <chose_example_path>"
        exit 1
    fi
    chosen_example_path=$1

    echo

    # Check if argocd/overlays directory exists and count subdirectories
    overlays_dir="${chosen_example_path}/argocd/overlays"
    if [ -d "$overlays_dir" ]; then
        overlay_count=$(find "$overlays_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
        if [ "$overlay_count" -gt 1 ]; then
            # multiple overlay options found
            # let the user choose which one to deploy
            echo "Multiple overlay options found in ${overlays_dir}:"
            PS3="Choose an option you wish to deploy?"
            select chosen_option in $(basename -a ${overlays_dir}/*/);
            do
                test -n "${chosen_option}" && break;
                echo ">>> Invalid Selection";
            done
            echo "You selected ${chosen_option}"
        elif [ "$overlay_count" -eq 1 ]; then
            # one overlay option found
            # use the default one
            chosen_option=$(basename $(find "$overlays_dir" -mindepth 1 -maxdepth 1 -type d))
            echo "One overlay option found in ${overlays_dir}: ${chosen_option}"
        else
            echo "No overlay options found in ${overlays_dir}"
            exit 2
        fi

        CHOSEN_EXAMPLE_OPTION_PATH=${overlays_dir}/${chosen_option}
    else
        echo "Argocd folder was not found: ${overlays_dir}"
        exit 2
    fi
}

deploy_example() {
    if [ -z "$1" ]; then
        echo "Error: No option provided to deploy_example()"
        echo "Usage: deploy_example <chose_example_overlay_path>"
        exit 1
    fi
    chose_example_overlay_path=$1

    echo
    echo "Deploying example: ${chose_example_overlay_path}"

    sed_args=()
    for sub in "${subs[@]}"; do
        key="${sub%%=*}"
        val="${sub#*=}"
        sed_args+=("-e" "s|${key}|${val}|g")
    done

    kustomize build ${chose_example_overlay_path} \
        | sed "${sed_args[@]}" \
        | tee \
        | oc apply -n ${ARGOCD_NS} -f -
}

detect_git_repository() {
    echo "--- Detecting Git repository configuration ---"
    
    CURRENT_REPO_URL=$(git config --get remote.origin.url)
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

    if [ -z "$CURRENT_REPO_URL" ] || [ -z "$CURRENT_BRANCH" ]; then
        echo "Warning: Could not determine current Git repository URL or branch."
        echo "Using default repository configuration."
        CURRENT_REPO_URL="https://github.com/redhat-ai-services/ai-accelerator-examples.git"
        CURRENT_BRANCH="main"
    fi

    echo "Repository configuration:"
    echo "  Repository URL: ${CURRENT_REPO_URL}"
    echo "  Branch: ${CURRENT_BRANCH}"

    # Initialize global substitutions
    subs+=(
        "GIT_REPO_URL=${CURRENT_REPO_URL}"
        "GIT_BRANCH=${CURRENT_BRANCH}"
    )
}

main() {
    choose_example

    # Initialize subs array
    subs=()

    # Always detect git repository
    detect_git_repository

    if [ -f "${CHOSEN_EXAMPLE_PATH}/$chosen_example.sh" ]; then
        source "${CHOSEN_EXAMPLE_PATH}/$chosen_example.sh"
    fi

    # Has prerequisite steps?
    [[ $(type -t prerequisite) == function ]] && prerequisite

    choose_example_option ${CHOSEN_EXAMPLE_PATH}
    deploy_example ${CHOSEN_EXAMPLE_OPTION_PATH}

    # Has post-install steps?
    [[ $(type -t post-install-steps) == function ]] && post-install-steps
}

check_oc_login
main