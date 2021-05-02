# Server Setup

## Infrastructure

### VLS

Terraform is used to create a VLS in Hetzner Cloud and a add set of ssh keys to access the VLS. The used module is documented [here](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs), but you may want to consult [normal API doc](https://docs.hetzner.cloud/#overview) because it is more verbose and allows you to get IDs and other crucial stuff. A new API Key can be created in [Hetzner Cloud console](https://console.hetzner.cloud). Make sure to copy it because it is only showed to you once.

```shell
cd infrastructure
terraform init 
terraform apply -var "hcloud_token=YOUR_API_TOKEN"

# to print output
terraform output

# to remove vls
terraform destroy -var "hcloud_token=YOUR_API_TOKEN"
```

### DNS

The DNS is created manually and is configured via [cloudflare webui](https://dash.cloudflare.com/login). There is an A and an AAAA entry configured in cloudflare which map the domain name to the vls ipv4 and ipv6 address. You may need to configure a new CNAME for every subdomain you want to use.

### Domain

The domain weyrich.dev is bought on namecheap (14€ a year) and can be managed via the [webui](https://www.namecheap.com/myaccount/login/?ReturnUrl=%2f). To configure namecheap to use the cloudflare DNS follow the [instructions](https://www.namecheap.com/support/knowledgebase/article.aspx/767/10/how-to-change-dns-for-a-domain/).

## Provisioning

### k3s

[k3s](https://rancher.com/docs/k3s/latest/en/) is installed with [k3s-ansible](https://github.com/k3s-io/k3s-ansible.

```shell
cd provisioning/k3s-ansible
# test connection
ansible -i inventory/hetzner/hosts.ini all -m ping
# install k3s
ansible-playbook site.yml -i inventory/hetzner/hosts.ini

# To connect to the cluster copy the ~/.kube/config from the server to your local ~/.kube/config
# check connection to k3s with
kubectl config get-contexts
```

*I would have used packer to create a ready provisioned os image, but Hetzner only allows standard images for installation.*

### sealedSecrets

- [Bitnami sealedSecrets](https://github.com/bitnami-labs/sealed-secrets) allows you to save encrypted secrets in your repository which will get decrypted inside of the k8s cluster.
- It consists of a [kubeseal](https://github.com/bitnami-labs/sealed-secrets#usage) cli and a operator which runs in the cluster. The installation is described [here](https://github.com/bitnami-labs/sealed-secrets/releases)
- check [release notes](https://github.com/bitnami-labs/sealed-secrets/blob/main/RELEASE-NOTES.md) before updating

### install

```
# install cli
brew install kubeseal@0.15.0

# install operator 
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets --namespace kube-system sealed-secrets/sealed-secrets --version 1.15.0-r3

# (optional) you can download the public cert which is used to encrypt the secrets and use it with the --cert flag
kubeseal \
 --controller-name=sealed-secrets \
 --controller-namespace=kube-system \
 --fetch-cert > sealedSecretCert.pem
```

### usage examples

- You can create a sealedSecret resource either
  1. by converting a existing secret resource (yaml) to a sealedSecret
  2. by encrypting a string which you can use as a value in a sealedSecret resource (raw mode)
- sealedSecrets support three types of [scopes](https://github.com/bitnami-labs/sealed-secrets#scopes) for encryption:
  1. strict (default) - the secret must be sealed with exactly the same name and namespace.
  2. namespace-wide - you can freely rename the sealed secret within a given namespace.
  3. cluster-wide - the secret can be unsealed in any namespace and can be given any name.

```shell
# creation from secret
kubectl create secret generic secret-name --dry-run=client --from-literal=foo=bar -o yaml | \
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
 --format yaml > mysealedsecret.yaml

# creation of single value in raw mode

## scope strict
echo -n foo | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
  --raw --from-file=/dev/stdin \
  --namespace apps --name strictsecret
 
## namespace-wide
echo -n foo | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
  --raw --from-file=/dev/stdin \
  --namespace apps --scope namespace-wide

## cluster-wide
echo -n foo | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
  --raw --from-file=/dev/stdin \
  --scope namespace-wide
```

### cert-manager (letsencrypt)

- [cert-manager](https://cert-manager.io/) is a k8s native x.509 certificate manager.
- It uses custom resource definitions
  - [Issuer/ClusterIssuer](https://cert-manager.io/docs/concepts/issuer/) represent CAs. A ClusterIssuer works for multiple namespaces. A normal Issuer only for one namespace.
  - [Certificate](https://cert-manager.io/docs/concepts/certificate/) represents the x509 certificates which will be renewed. It will be used to derive a k8s secret.
- It can be used to deploy ACME (Let's Encrypt) certificates.

1. Install it with the [official helm chart](https://artifacthub.io/packages/helm/jetstack/cert-manager)
2. Configure [ACME Issuer with dns challenge for cloudflare](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
3. To automatically deliver a valid certificate to a ingress resource add the annotation `cert-manager.io/cluster-issuer: cloudflare-dns-acme-ca` and set a host with a secret under tls. [Here](https://cert-manager.io/docs/usage/ingress/)) are the complete instructions.

```shell
# 1. Install cert-manager via helm
kubectl create namespace cert-manager

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true

# 2. configure acme with cloudflare
kubectl apply --namespace cert-manager -f ./provisioning/ca-acme-dns.yaml 

## the value for api-token in the sealedSecret was create in the following way
### get your api token from https://dash.cloudflare.com/profile/api-tokens
### generate the sealedSecret from the secret
TMP_API_TOKEN=<cloudflare_api_token>
kubectl create secret generic cloudflare-api-token-secret \
    --namespace cert-manager --from-literal=api-token=$TMP_API_TOKEN \
    --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
  --scope=strict --namespace cert-manager \
  --name cloudflare-api-token-secret --format yaml
```

### argocd

1. [Install argo](https://argo-cd.readthedocs.io/en/stable/getting_started/#1-install-argo-cd)
2. Disable TLS on argo-server (--insecure) to work with an ingress with tls termination
2. [Configure ingress resource with certmanager](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#ssl-passthrough-with-cert-manager-and-lets-encrypt)

```shell
# 1.
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. disable tls on argocd server
kubectl patch -n argocd deployment argocd-server --type json -p='[ { "op": "replace", "path":"/spec/template/spec/containers/0/command","value": ["argocd-server","--staticassets","/shared/app","--insecure"] }]' 

# 3. configure ingress which uses tls handoff (default behaviour of traefik)
kubectl apply -f ./provisioning/argocd-ingress.yaml

# 4. get password for admin user
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 

# 5. change password with argocd cli
brew install argocd
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd login localhost:8080
kubectl -n argocd delete secret argocd-initial-admin-secret
```

### Drone CI

1. add [drone helm chart](https://github.com/drone/charts)
2. install [drone server](https://github.com/drone/charts/tree/master/charts/drone)
  - [Generate RPC secret](https://readme.drone.io/server/provider/github/#create-a-shared-secret)
  - [Get Client id and secret from github](https://github.com/settings/developers)
  - create sealedSecret
3. install [drone k8 secrets extension](https://github.com/drone/charts/blob/master/charts/drone-kubernetes-secrets/docs/install.md)
  - set env variable SECRET_KEY to the value of the rpc secret
4. install [drone k8s runner](https://github.com/drone/charts/blob/master/charts/drone-runner-kube/docs/install.md)
  - set rpc secret with DRONE_RPC_SECRET env
  - configure drone k8s secret plugin
5. allow drone service account of runner and secret extension to create secrets. The name of the service account is by default the name of the namespace in which the pods are deployed.

```shell
# 1. add helm repo
helm repo add drone https://charts.drone.io
helm repo update

# 2. install drone server
kubectl create secret generic drone-secrets --dry-run=client --from-literal=DRONE_GITHUB_CLIENT_ID=<REPLACE> --from-literal=DRONE_GITHUB_CLIENT_SECRET=<REPLACE> --from-literal=DRONE_RPC_SECRET=<REPLACE> -o yaml | \
 kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system  \
--namespace droneci --name drone-secrets --format yaml > drone-secrets.yaml

kubectl apply -f ./provisioning/droneci/drone-secrets.yaml -n droneci

helm install drone drone/drone --namespace droneci --values drone-values.yaml

# 3. install drone k8s secret extension
helm install drone-kubernetes-secrets drone/drone-kubernetes-secrets --namespace droneci --set extraSecretNamesForEnvFrom={"drone-secrets"} --set rbac.secretNamespace="droneci"

# 4. install k8s runner
helm install drone-runner-kube drone/drone-runner-kube --namespace droneci --values drone-runner-values.yaml

```

- [How to use secrets in pipelines](https://docs.drone.io/secret/external/kubernetes/)
- The secret are expected to be in the droneci namespace

## CI/CD

Use drone ci to deploy the following applications in k3s:

- [kvb]()
- [kvb-ui]()
- [spotidash]()

## Documentation
