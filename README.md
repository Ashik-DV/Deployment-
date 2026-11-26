# Blue-Green Deployment on Azure AKS

A learning project based on the traffic architecture discussed in the EMA v5 Canary document, adapted for **Blue-Green deployment**.

## Architecture

Internet -> Azure Application Gateway -> Kong Gateway -> Gateway API HTTPRoute -> Green or Blue Kubernetes Service -> Pods.

- **Application Gateway:** public HTTP entry point; forwards to Kong's private LoadBalancer IP.
- **Kong Proxy:** receives and routes application traffic.
- **Kong Ingress Controller:** watches Gateway API resources and configures Kong.
- **HTTPRoute:** switches traffic between Green and Blue (100/0).
- **AKS:** separate system, Blue and Green node pools. Blue and Green pools are tainted and workloads tolerate only their matching taint.
- **Argo CD:** syncs `kubernetes/base` from Git.
- **Dynatrace:** intentionally excluded from this first hands-on.

This is a practice implementation, not the company's actual EMA v5 environment.

## Repository layout

- `infrastructure/terraform`: Azure VNet, AKS, node pools, ACR and Application Gateway.
- `infrastructure/kong`: Kong Helm values and Gateway API Gateway resources.
- `kubernetes/base`: Green and Blue Deployments, Services and HTTPRoute.
- `argocd`: Argo CD Application.
- `scripts`: switch traffic between environments.

## Prerequisites

Azure CLI, Terraform >= 1.6, kubectl, Helm, and an Azure subscription with quota for the selected VM size and Application Gateway Standard_v2. The example defaults to `Standard_D2as_v5`; confirm quota for the `standardDASv5Family` in your subscription before applying.

## 1. Azure login and quota check

```bash
az login
az account show --output table
az vm list-usage --location malaysiawest --output table
```

Check your subscription's regional vCPU quota and the selected VM family before creating anything. Change `location` and `node_vm_size` in `infrastructure/terraform/terraform.tfvars` to values available in your subscription. Your earlier `Standard_DSv5` quota issue is why this example uses the separate `DASv5` family; this is not a guarantee that your subscription has quota.

## 2. Create Azure infrastructure

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

Review the plan and estimated cost before running `terraform apply`. Application Gateway Standard_v2 and three AKS nodes incur ongoing charges.

After apply:

```bash
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw aks_name) --overwrite-existing
kubectl get nodes -o wide
```

## 3. Install Gateway API and Kong

Install Gateway API CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

Install Kong (from repository root):

```bash
helm repo add kong https://charts.konghq.com
helm repo update
helm upgrade --install kong kong/ingress --namespace kong --create-namespace -f infrastructure/kong/values.yaml
kubectl apply -f infrastructure/kong/gatewayclass.yaml
kubectl apply -f infrastructure/kong/gateway.yaml
kubectl -n kong get pods,svc
```

Wait for the Kong Service to receive the configured private IP `10.20.1.10`. If it does not, inspect Service events and Azure subnet/IP allocation before proceeding.

## 4. Deploy the application and route

The manifests are designed to be synced by Argo CD. For a first manual test:

```bash
kubectl apply -f kubernetes/base/namespace.yaml
kubectl apply -f kubernetes/base/green.yaml
kubectl apply -f kubernetes/base/blue.yaml
kubectl apply -f kubernetes/base/httproute.yaml
kubectl -n blue-green get pods -o wide
kubectl -n blue-green get svc
kubectl -n blue-green get httproute
```

Green is initially active (100%) and Blue is standby (0%). Both Deployments are scheduled only on their matching node pools.

## 5. Test through Application Gateway

Get the public IP:

```bash
cd infrastructure/terraform
terraform output -raw application_gateway_public_ip
```

For a temporary test, map the public IP to `bluegreen.example.com` in your local hosts file, then open `http://bluegreen.example.com`. The Application Gateway listener is HTTP-only for this learning setup; configure a certificate and HTTPS listener before production use.

## 6. Switch traffic

Edit `kubernetes/base/httproute.yaml` so Green has weight 0 and Blue has weight 100, then commit and push. To roll back, restore Green 100 and Blue 0.

Helper scripts:

```bash
./scripts/switch-to-blue.sh
./scripts/switch-to-green.sh
```

Commit and push the resulting HTTPRoute change. If Argo CD is configured, it will sync the Git state to AKS.

## 7. Install Argo CD and connect Git

Install Argo CD using its official installation instructions, then apply:

```bash
kubectl apply -f argocd/application.yaml
kubectl -n argocd get applications
```

The Application tracks the `main` branch. Merge your tested changes into `main` for Argo CD to deploy them.

## Important implementation notes

1. Confirm the Kong Helm chart values and Gateway API compatibility for the chart/controller version you install. Validate with `helm show values kong/ingress` and inspect the rendered manifests before production use.
2. Application Gateway's backend pool uses the reserved private Kong IP. The Kong Service must successfully claim that IP from the AKS subnet.
3. The initial Application Gateway probe checks `/`; verify its backend health after Kong and the HTTPRoute are ready.
4. The initial listener is HTTP only. Add HTTPS/TLS for real deployments.
5. The Terraform network profile uses Azure CNI Overlay with Cilium. Confirm support in your selected AKS region/version.
6. The example uses one node in each pool for a small lab. It still requires enough regional and VM-family quota for all three nodes.
7. Do not commit real credentials, kubeconfigs, state files, or populated `terraform.tfvars`.

## Cleanup

When finished, destroy the Azure resources to avoid ongoing charges:

```bash
cd infrastructure/terraform
terraform destroy
```
