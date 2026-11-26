# EMA-style Blue-Green Deployment on Azure AKS

A learning project that recreates the key traffic path from the EMA v5 architecture and adapts it for **Blue-Green deployments**.

## Architecture

Internet -> Azure Application Gateway -> Kong Gateway -> Gateway API HTTPRoute -> Blue or Green Kubernetes Service -> Pods.

AKS uses separate system, blue, and green node pools. Argo CD manages Kubernetes manifests from Git. Dynatrace is intentionally out of scope for the first version.

## Project status

Initial repository setup. Infrastructure and manifests will be added in the implementation branch.

## Important

- This is a practice implementation, not a copy of the company's EMA v5 environment.
- Azure resources can incur charges. Review the Terraform plan before applying it.
- The Terraform configuration is parameterized; confirm your subscription quota and supported VM sizes before provisioning.
