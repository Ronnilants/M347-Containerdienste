#!/bin/bash
# =============================================================
# KN08 Setup Script - Vollautomatisches Cluster-Setup
# Läuft in AWS CloudShell oder auf jedem Linux mit AWS CLI
# Autor: Ronnilants
# =============================================================
# USAGE:
#   1. AWS CloudShell öffnen (console.aws.amazon.com → CloudShell)
#   2. Dieses Script hochladen oder einfügen
#   3. chmod +x setup-kn08.sh && bash setup-kn08.sh
# =============================================================

set -e

# ─── KONFIGURATION ───────────────────────────────────────────
AMI_ID="ami-0e2c8caa4b6378d8c"      # Ubuntu 22.04 LTS us-east-1
INSTANCE_TYPE="t3.medium"
KEY_NAME="vockey"                     # AWS Academy Key (anpassen!)
REGION="us-east-1"
SG_NAME="kn08-sg"
# ─────────────────────────────────────────────────────────────

echo "============================================"
echo "  KN08 Kubernetes Cluster Setup"
echo "============================================"

# ── 1. Security Group erstellen ──────────────────────────────
echo "[1/6] Security Group erstellen..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "KN08 MicroK8s Cluster" \
  --region $REGION \
  --query 'GroupId' --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' --output text)

echo "  Security Group: $SG_ID"

# Ports öffnen (idempotent - Fehler ignorieren falls schon offen)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 16443 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0 --region $REGION 2>/dev/null || true
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol all --source-group $SG_ID --region $REGION 2>/dev/null || true
echo "  Ports geöffnet: 22, 80, 443, 16443, 30000-32767"

# ── 2. EC2 Instanzen starten ─────────────────────────────────
echo "[2/6] EC2 Instanzen starten (1 Master + 2 Worker)..."

MASTER_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kn08-master},{Key=Role,Value=master}]' \
  --region $REGION \
  --query 'Instances[0].InstanceId' --output text)

WORKER1_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kn08-worker1},{Key=Role,Value=worker}]' \
  --region $REGION \
  --query 'Instances[0].InstanceId' --output text)

WORKER2_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=kn08-worker2},{Key=Role,Value=worker}]' \
  --region $REGION \
  --query 'Instances[0].InstanceId' --output text)

echo "  Master:  $MASTER_ID"
echo "  Worker1: $WORKER1_ID"
echo "  Worker2: $WORKER2_ID"

# ── 3. Warten bis Instanzen laufen ───────────────────────────
echo "[3/6] Warte bis Instanzen bereit sind..."
aws ec2 wait instance-running --instance-ids $MASTER_ID $WORKER1_ID $WORKER2_ID --region $REGION
sleep 20

MASTER_IP=$(aws ec2 describe-instances --instance-ids $MASTER_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
WORKER1_IP=$(aws ec2 describe-instances --instance-ids $WORKER1_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
WORKER2_IP=$(aws ec2 describe-instances --instance-ids $WORKER2_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

MASTER_PRIVATE=$(aws ec2 describe-instances --instance-ids $MASTER_ID --region $REGION --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
WORKER1_PRIVATE=$(aws ec2 describe-instances --instance-ids $WORKER1_ID --region $REGION --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
WORKER2_PRIVATE=$(aws ec2 describe-instances --instance-ids $WORKER2_ID --region $REGION --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo "  Master:  $MASTER_IP (privat: $MASTER_PRIVATE)"
echo "  Worker1: $WORKER1_IP (privat: $WORKER1_PRIVATE)"
echo "  Worker2: $WORKER2_IP (privat: $WORKER2_PRIVATE)"

# ── 4. SSH Key ermitteln ──────────────────────────────────────
echo "[4/6] SSH Key suchen..."
KEY_FILE=""
for p in ~/.ssh/labsuser.pem ~/.ssh/vockey.pem ~/labsuser.pem ~/vockey.pem; do
  if [ -f "$p" ]; then
    KEY_FILE="$p"
    chmod 400 "$KEY_FILE"
    echo "  Key gefunden: $KEY_FILE"
    break
  fi
done

if [ -z "$KEY_FILE" ]; then
  echo ""
  echo "  WICHTIG: Kein SSH Key gefunden!"
  echo "  Bitte labsuser.pem in CloudShell hochladen:"
  echo "  → CloudShell → Actions → Upload File → labsuser.pem"
  echo "  Dann script neu starten."
  exit 1
fi

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=15"

# Warten bis SSH verfügbar
echo "  Warte auf SSH-Verbindung..."
for i in $(seq 1 20); do
  if $SSH ubuntu@$MASTER_IP "echo ok" 2>/dev/null | grep -q ok; then
    echo "  SSH bereit!"
    break
  fi
  echo "  Versuch $i/20..."
  sleep 15
done

# ── 5. MicroK8s installieren ──────────────────────────────────
INSTALL_SCRIPT='
set -e
echo "=== MicroK8s installieren ==="
sudo snap install microk8s --classic --channel=1.31/stable
sudo usermod -aG microk8s ubuntu
sudo microk8s status --wait-ready --timeout 120
echo "=== MicroK8s bereit ==="
'

echo "[5/6] MicroK8s auf allen Nodes installieren (parallel)..."
$SSH ubuntu@$MASTER_IP "$INSTALL_SCRIPT" &
$SSH ubuntu@$WORKER1_IP "$INSTALL_SCRIPT" &
$SSH ubuntu@$WORKER2_IP "$INSTALL_SCRIPT" &
wait
echo "  MicroK8s installiert auf allen 3 Nodes"

# ── 6. Cluster aufbauen ───────────────────────────────────────
echo "[6/6] Cluster aufbauen..."

# Join-Tokens generieren
JOIN1=$($SSH ubuntu@$MASTER_IP "sudo microk8s add-node --format short 2>/dev/null | grep '$WORKER1_PRIVATE\|--worker' | head -1 || sudo microk8s add-node 2>/dev/null | grep 'microk8s join' | head -1")
sleep 5
JOIN2=$($SSH ubuntu@$MASTER_IP "sudo microk8s add-node --format short 2>/dev/null | grep '$WORKER2_PRIVATE\|--worker' | head -1 || sudo microk8s add-node 2>/dev/null | grep 'microk8s join' | head -1")

# Worker joinen
$SSH ubuntu@$WORKER1_IP "sudo $JOIN1 --worker 2>/dev/null || sudo $JOIN1" &
sleep 5
$SSH ubuntu@$WORKER2_IP "sudo $JOIN2 --worker 2>/dev/null || sudo $JOIN2" &
wait

sleep 20
echo "  Cluster Status:"
$SSH ubuntu@$MASTER_IP "sudo microk8s kubectl get nodes"

# ── 7. Kubernetes Ressourcen deployen ────────────────────────
echo ""
echo "=== Kubernetes Deployment ==="

# SQL Datei übertragen
cat << 'SQLEOF' > /tmp/m347_KN08_DB.sql
SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

CREATE Database m347kn08;
use m347kn08;

CREATE TABLE `users` (
  `id` int NOT NULL,
  `name` varchar(50) NOT NULL,
  `amount` int not null
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

CREATE TABLE `friends` (
  `user_id1` int NOT NULL,
  `user_id2` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

ALTER TABLE `users` ADD PRIMARY KEY (`id`);
ALTER TABLE `friends` ADD PRIMARY KEY (`user_id1`, `user_id2`);

insert into users values (1,'Rene',30),(2,'Sam',87),(3,'Sara',54),(4,'Yannis',54),(5,'Sabrina',22);
insert into friends values (1,3),(1,4),(1,5),(3,2),(3,4),(5,2),(5,4);
COMMIT;
SQLEOF

scp -i $KEY_FILE -o StrictHostKeyChecking=no /tmp/m347_KN08_DB.sql ubuntu@$MASTER_IP:/tmp/

# K8s YAML auf Master erstellen und anwenden
$SSH ubuntu@$MASTER_IP "mkdir -p /tmp/k8s"

# YAML Dateien via Heredoc übertragen
$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/mysql-secret.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
stringData:
  mysql-root-password: rootpass123
EOF

$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/mysql.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: mysql-root-password
        - name: MYSQL_DATABASE
          value: m347kn08
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-service
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
EOF

$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/account.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: account-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: account
  template:
    metadata:
      labels:
        app: account
    spec:
      containers:
      - name: account
        image: ronnilants/kn08-account:latest
        ports:
        - containerPort: 8080
        env:
        - name: ConnectionString
          value: "Server=mysql-service;Database=m347kn08;User ID=root;Password=rootpass123;"
---
apiVersion: v1
kind: Service
metadata:
  name: account-service
spec:
  selector:
    app: account
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: account-nodeport
spec:
  type: NodePort
  selector:
    app: account
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30080
EOF

$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/buysell.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: buysell-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: buysell
  template:
    metadata:
      labels:
        app: buysell
    spec:
      containers:
      - name: buysell
        image: ronnilants/kn08-buysell:latest
        ports:
        - containerPort: 8002
        env:
        - name: ACCOUNT_URL
          value: "http://account-service:8080"
---
apiVersion: v1
kind: Service
metadata:
  name: buysell-service
spec:
  selector:
    app: buysell
  ports:
  - port: 8002
    targetPort: 8002
---
apiVersion: v1
kind: Service
metadata:
  name: buysell-nodeport
spec:
  type: NodePort
  selector:
    app: buysell
  ports:
  - port: 8002
    targetPort: 8002
    nodePort: 30082
EOF

$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/sendreceive.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sendreceive-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sendreceive
  template:
    metadata:
      labels:
        app: sendreceive
    spec:
      containers:
      - name: sendreceive
        image: ronnilants/kn08-sendreceive:latest
        ports:
        - containerPort: 8003
        env:
        - name: ACCOUNT_URL
          value: "http://account-service:8080"
---
apiVersion: v1
kind: Service
metadata:
  name: sendreceive-service
spec:
  selector:
    app: sendreceive
  ports:
  - port: 8003
    targetPort: 8003
---
apiVersion: v1
kind: Service
metadata:
  name: sendreceive-nodeport
spec:
  type: NodePort
  selector:
    app: sendreceive
  ports:
  - port: 8003
    targetPort: 8003
    nodePort: 30083
EOF

# Frontend YAML dynamisch mit Master-IP
$SSH ubuntu@$MASTER_IP "cat > /tmp/k8s/frontend.yaml << FEOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: ronnilants/kn08-frontend:v3
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30000
FEOF"

# Alle Ressourcen anwenden
echo "  YAML Dateien anwenden..."
$SSH ubuntu@$MASTER_IP "
  sudo microk8s kubectl apply -f /tmp/k8s/mysql-secret.yaml
  sudo microk8s kubectl apply -f /tmp/k8s/mysql.yaml
  sudo microk8s kubectl apply -f /tmp/k8s/account.yaml
  sudo microk8s kubectl apply -f /tmp/k8s/buysell.yaml
  sudo microk8s kubectl apply -f /tmp/k8s/sendreceive.yaml
  sudo microk8s kubectl apply -f /tmp/k8s/frontend.yaml
"

# ── 8. Datenbank importieren ──────────────────────────────────
echo "  Warte auf MySQL Pod..."
$SSH ubuntu@$MASTER_IP "
  for i in \$(seq 1 20); do
    STATUS=\$(sudo microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ \"\$STATUS\" = 'Running' ]; then echo 'MySQL bereit'; break; fi
    echo \"Warte... (\$i/20) Status: \$STATUS\"
    sleep 10
  done
"

$SSH ubuntu@$MASTER_IP "
  MYSQL_POD=\$(sudo microk8s kubectl get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
  sudo microk8s kubectl exec -i \$MYSQL_POD -- mysql -uroot -prootpass123 < /tmp/m347_KN08_DB.sql 2>/dev/null || true
  sudo microk8s kubectl exec \$MYSQL_POD -- mysql -uroot -prootpass123 m347kn08 -e 'SELECT * FROM users;' 2>/dev/null
"

# ── 9. Zusammenfassung ────────────────────────────────────────
echo ""
echo "============================================"
echo "  SETUP ABGESCHLOSSEN!"
echo "============================================"
echo ""
echo "  Master IP:  $MASTER_IP"
echo "  Worker1 IP: $WORKER1_IP"
echo "  Worker2 IP: $WORKER2_IP"
echo ""
echo "  Links:"
echo "  → Frontend:  http://$MASTER_IP:30000"
echo "  → Swagger:   http://$MASTER_IP:30080/swagger"
echo ""
echo "  Pods Status:"
$SSH ubuntu@$MASTER_IP "sudo microk8s kubectl get pods"
echo ""
echo "  Instanz IDs (zum Stoppen/Starten):"
echo "  Master:  $MASTER_ID"
echo "  Worker1: $WORKER1_ID"
echo "  Worker2: $WORKER2_ID"
echo ""
echo "  Instanzen stoppen wenn fertig:"
echo "  aws ec2 stop-instances --instance-ids $MASTER_ID $WORKER1_ID $WORKER2_ID --region $REGION"
echo "============================================"
