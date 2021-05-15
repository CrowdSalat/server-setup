# droneci-umbrella

Deployed with [Argocd application](../../argo-app-of-apps).

## Usage

```shell
helm dep up
helm template drone/drone -n droneci
```

## Manually install helm releases

1. add [drone helm chart](https://github.com/drone/charts)
2. install [drone server](https://github.com/drone/charts/tree/master/charts/drone)
  - [Generate RPC secret](https://readme.drone.io/server/provider/github/#create-a-shared-secret)
  - [Get Client id and secret from github](https://github.com/settings/developers)
  - create sealedSecret
3. install [drone k8 secrets extension](https://github.com/drone/charts/blob/master/charts/drone-kubernetes-secrets/docs/install.md)
  - set env variable SECRET_KEY to the value of the rpc secret
4. install [drone k8s runner](https://github.com/drone/charts/blob/master/charts/drone-runner-kube/docs/install.md)
  - set rpc secret with DRONE_RPC_SECRET env
  - configure drone k8s secret plugin (DRONE_SECRET_PLUGIN_ENDPOINT & DRONE_SECRET_PLUGIN_TOKEN)
5. add seret which contains dockerhub credentials

```shell
# 1. add helm repo
helm repo add drone https://charts.drone.io
helm repo update

# 2. install drone server
kubectl create secret generic drone-secrets --dry-run=client --from-literal=DRONE_GITHUB_CLIENT_ID=<REPLACE> --from-literal=DRONE_GITHUB_CLIENT_SECRET=<REPLACE> --from-literal=DRONE_RPC_SECRET=<REPLACE> -o yaml | \
 kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system  \
--namespace droneci --name drone-secrets --format yaml > secret-drone.yaml

kubectl apply -f secret-drone.yaml -n droneci

helm install drone drone/drone --namespace droneci --values values-drone.yaml

# 3. install drone k8s secret extension
helm install drone-kubernetes-secrets drone/drone-kubernetes-secrets --namespace droneci --values values-drone-secret-plugin.yaml

# 4. install k8s runner
helm install drone-runner-kube drone/drone-runner-kube --namespace droneci --values values-drone-runner.yaml.yaml

# 5. create and apply secret
kubectl create secret generic dockerhub --dry-run=client --from-literal=username=<REPLACE> --from-literal=password=<REPLACE> -o yaml | \
 kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system  \
--namespace droneci --name dockerhub --format yaml > secret-dockerhub.yaml

kubectl apply -f ./secret-dockerhub.yaml -n droneci