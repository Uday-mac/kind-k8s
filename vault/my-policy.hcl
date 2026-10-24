kubectl create namespace vault

helm repo add hashicorp https://helm.releases.hashicorp.com

  helm install vault hashicorp/vault \
        --set='server.dev.enabled=true' \
        --set='ui.enabled=true' \
        --set='ui.serviceType=LoadBalancer' \
        --namespace vault

kubectl exec -it vault-0 -n vault -- /bin/sh 

cat <<EOF > /home/vault/db-read-policy.hcl
path "secret/data/db" {
  capabilities = ["read"]
}
EOF

vault policy write db-read-policy - <<'EOF'
path "secret/data/db" {
  capabilities = ["read"]
}
EOF



vault policy write db-read-policy /home/vault/db-read-policy.hcl

vault auth enable kubernetes

vault write auth/kubernetes/config \
   token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
   kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
   kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault write auth/kubernetes/role/vault-role \
   bound_service_account_names=vault-sa \
   bound_service_account_namespaces=vault \
   policies=db-read-policy \
   ttl=1h

vault kv put secret/db username=uday password=password

apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: vault
  name: vault-sa
  labels:
    app: db-secret

---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-test
  labels:
    app: db-secret
  namespace: vault
spec:
  selector:
    matchLabels:
      app: db-secret  
  replicas: 1
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/agent-inject-status: "update"
        vault.hashicorp.com/agent-inject-secret-db: "secret/data/db"
        vault.hashicorp.com/agent-inject-template-data-db: |
          {{- with secret "secret/data/db" -}}
          username={{ .Data.data.username }}
          password={{ .Data.data.password }}
          {{- end }}
        vault.hashicorp.com/role: "vault-role"
      labels:
        app: db-secret
    spec:
      serviceAccountName: vault-sa
      containers:
      - name: nginx
        image: nginx