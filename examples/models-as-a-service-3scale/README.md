# Models as a Service Example

This example deploys a "Models as a Service" (MaaS) environment using Red Hat OpenShift. It provides a complete setup for serving and managing machine learning models as scalable, secure, and monetizable APIs.

## Architecture Overview

This solution creates a comprehensive API management platform for machine learning models by integrating:

- **3scale API Management** as the API gateway for access control, rate limiting, and analytics.
- **Model Serving Infrastructure** for hosting and serving machine learning models.
- **OpenShift Data Foundation (ODF)** for persistent storage requirements. Red Hat OpenShift Data Foundation (ODF) is the recommended solution for providing RWX storage (i.e. RWX storage is required by 3Scale).
- **GitOps-based deployment** using ArgoCD for automated configuration management.

## Included Components

This example automates the deployment and configuration of the following components:

*   **3scale API Management**: For API gateway functionality, including access control, rate limiting, and analytics.
*   **Model Serving (LLMaaS)**: Infrastructure for hosting and serving machine learning models, including a pre-deployed Llama 3.2 1B Instruct model.

## Prerequisites

Before you begin, ensure you have the following:

*   An OpenShift cluster with cluster-admin privileges.
*   **OpenShift Data Foundation (ODF)** installed and configured to provide ReadWriteMany (RWX) storage.
*   The OpenShift GitOps operator installed.
*   The following command-line tools installed locally:
    *   `oc`
    *   `git`
    *   `jq`
    *   `yq`

Note: A quick way to get most of this configured via gitops is to use the [ai-accelerator](https://github.com/redhat-ai-services/ai-accelerator) github project. The Openshift Gitops operator and RHOAI and related operators are configured for you out of the box. However, ODF operator along with a suitable storage system must be applied to the cluster prior to running the ai-accelerator project bootstrapping or you can tweak the ai-accelerator kustomize files or the ai-accelerator bootstrap script so that ODF/StorageSystem gets deployed prior to other MaaS components binding to persistent volumes.

## Deployment

To deploy this example, clone this repository and run the bootstrap script from the root directory:

```bash
./bootstrap.sh
```

Then select the `models-as-a-service-3scale` example from the menu.

The script will guide you through the following pre-deployment configuration steps:

1.  **Git Repository Configuration**: The script will automatically detect your current Git repository URL and branch (in case of fork scenario) to configure the ArgoCD ApplicationSet.
2.  **Commit and Push**: You will be prompted to commit and push these configuration changes to your repository. This step is required for the GitOps-based deployment to work correctly. The script uses a Git credential helper to cache your credentials temporarily.

The bootstrap script then deploys the MaaS components using OpenShift GitOps.

## Post-Installation

After the script executes, the ArgoCD Application components perform several post-installation tasks automatically during syncing such as:

*   Waits for all components (3scale, Model Serving) to become ready.
*   Deploys a pre-configured Llama 3.2 1B Instruct model for immediate use.
*   Creates a admin portal user (username `admin` with password retrievable by the system-seed secret in 3scale namespace) for testing.
*   Creates a developer portal user (username `dev1` with password `openshift`) for testing.
*   Configures the 3scale developer portal with custom content to give it a look and feel more appropriate to MaaS.
*   3Scale Admin and Developer portal Openshift Routes in the 3scale namespace pointing to `system-provider` and `system-developer` Openshift Service's respectively.

### Pre-deployed Model

The deployment automatically includes:

*   **Llama 3.2 1B Instruct Model**: A pre-configured model served via vLLM with CPU optimization
*   **Model Configuration**: 
    - Max model length: 2000 tokens
    - CPU-optimized deployment (no GPU required)
    - Resource limits: 4 CPU cores, 8GB memory
*   **API Integration**: The model is automatically registered with 3scale as a backend service

## Accessing the Services

### 3scale Admin Portal

The 3scale admin portal provides access to API management features:

- **URL**: Available as a route in the `3scale` namespace
- **Credentials**: Retrieved from the `system-seed` secret
- **Features**: Backend management, product configuration, application plans, analytics

### Developer Portal

The 3scale developer portal provides API access for developers:

- **URL**: Available as a route in the `3scale` namespace
- **Test User**: `dev1` / `openshift`
- **Features**: API documentation, key management, usage analytics

### Model Service

The deployed Llama model is accessible through:

- **Internal Service**: `llama-32-1b-instruct-cpu` in the model-serving namespace
- **External Access**: Via 3scale API gateway with proper authentication
- **API Format**: OpenAI-compatible API endpoints

## Configuration

### Storage Requirements

This example requires ReadWriteMany (RWX) storage for 3scale system storage. OpenShift Data Foundation (ODF) is a prerequisite and must be installed before deployment.

### Custom Policies

The deployment includes custom policies for LLM token counting and monitoring:

- **LLM Metrics Policy**: Tracks token usage for OpenAI-compatible APIs
- **CORS Policy**: Handles cross-origin requests
- **Rate Limiting**: Configurable per application plan

### Security Configuration

- **API Keys**: Generated and managed through the developer portal
- **CORS**: Configured for web application integration
- **Access Control**: Managed through 3scale application plans

## Usage Examples

### Testing the Pre-deployed Model

1. Access the developer portal using `dev1` / `openshift`
2. Create an application to get API keys
3. Use the API keys to access the Llama model through 3scale gateway
4. Send requests to the model using OpenAI-compatible API format

### Registering Additional Models

To register additional models after initial deployment:

1. Access the 3scale admin portal
2. Navigate to Backends section
3. Create a new backend with your model's service URL
4. Create a corresponding product
5. Configure authentication and policies
6. Promote to production

### Managing API Access

1. Developers register through the developer portal
2. Select appropriate application plan
3. Receive API keys for authentication
4. Access models through 3scale gateway

### Monitoring and Analytics

- **Usage Statistics**: Available in 3scale admin portal
- **Token Counting**: Tracked for LLM models
- **Rate Limiting**: Enforced per application plan
- **Error Monitoring**: Built-in error tracking and reporting

## Troubleshooting

### Common Issues

**Storage Class Not Found**
- Ensure ODF is installed and provides RWX storage
- Verify storage class name is correct

**Model Service Not Ready**
- Check model serving pods in the model-serving namespace
- Verify resource limits are appropriate for your cluster
- Check for any resource constraints

**Developer Portal Access Issues**
- Verify the `dev1` account is created properly
- Check 3scale service status
- Ensure proper network connectivity

### Logs and Debugging

```bash
# Check 3scale component status
oc get pods -n 3scale

# View 3scale logs
oc logs -n 3scale deployment/apicast-production

# Check model serving status
oc get pods -n model-serving

# View model serving logs
oc logs -n model-serving deployment/llama-32-1b-instruct-cpu

# Check developer user status
oc get developeruser -n 3scale
```

## Cleanup

To remove the deployment:

```bash
# Remove ArgoCD applications
oc delete -k argocd/overlays/default -n openshift-gitops

# Remove namespaces (if not managed by ArgoCD)
oc delete namespace 3scale model-serving
```

## Additional Resources

- [3scale API Management Documentation](https://access.redhat.com/documentation/en-us/red_hat_3scale_api_management/)
- [OpenShift Data Foundation Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [OpenShift GitOps Documentation](https://access.redhat.com/documentation/en-us/openshift_gitops/)
- [vLLM Documentation](https://docs.vllm.ai/)

## Contributing

This example is part of the AI Accelerator Examples collection. For contribution guidelines and best practices, see the main repository documentation. 