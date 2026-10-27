# FreshBox SpA - Deployment Runbook (IaC)

Runbook ejecutable para aprovisionar y operar la arquitectura de la EP2 en
AWS Academy Learner Lab, región `us-east-1`.

> **Importante:** Las credenciales del Learner Lab son temporales. No las
> guardes en este archivo ni en el repositorio. Para AWS CLI exporta las tres
> variables temporales: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y
> `AWS_SESSION_TOKEN`.

## 1. Prerrequisitos y variables de entorno

Herramientas requeridas:

- AWS CLI v2 autenticado con una sesión vigente del Learner Lab.
- `jq`, `mysql` y `kubectl`.
- `eksctl`, `helm` y Docker (para operación local o validaciones).
- Permisos suficientes para VPC, EC2, RDS, EKS, IAM, ECR, CloudFormation y
  Elastic Load Balancing.

Comprobar la sesión y definir la región:

```bash
export REGION="us-east-1"
export AWS_DEFAULT_REGION="$REGION"

# ACCOUNT_ID se captura dinámicamente desde las credenciales activas.
export ACCOUNT_ID="$(aws sts get-caller-identity \
  --query Account --output text)"

aws sts get-caller-identity
printf 'ACCOUNT_ID=%s\nREGION=%s\n' "$ACCOUNT_ID" "$REGION"
```

Variables comunes del despliegue:

```bash
export PROJECT="freshbox"
export VPC_CIDR="10.0.0.0/22"
export AZ1="${REGION}a"
export AZ2="${REGION}b"

# IDs y nombres que se completan durante el runbook.
export VPC_ID=""
export IGW_ID=""
export PUBLIC_SUBNET_A=""
export PUBLIC_SUBNET_B=""
export APP_SUBNET_A=""
export APP_SUBNET_B=""
export DATA_SUBNET_A=""
export DATA_SUBNET_B=""
export SG_ALB=""
export SG_EKS=""
export SG_RDS=""
export RDS_ENDPOINT=""
```

## 2. Fase 1: red y seguridad perimetral (VPC /22 Multi-AZ)

### 2.1 VPC, Internet Gateway y subredes

La VPC usa seis subredes en dos zonas de disponibilidad:

| Capa | Zona A | Zona B | CIDR |
|---|---|---|---|
| Pública/ALB | `10.0.0.0/26` | `10.0.0.64/26` | ALB egress/NAT |
| Privada/app | `10.0.1.0/24` | `10.0.2.0/24` | EKS Graviton |
| Privada/data | `10.0.3.0/25` | `10.0.3.128/25` | RDS |

Crear la VPC y el Internet Gateway:

```bash
VPC_ID="$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT}-vpc}]" \
  --query 'Vpc.VpcId' --output text)"
export VPC_ID

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames '{"Value":true}'

IGW_ID="$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' --output text)"
export IGW_ID

aws ec2 attach-internet-gateway \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID"
```

Crear las seis subredes y aplicar las etiquetas requeridas por AWS Load
Balancer Controller:

```bash
PUBLIC_SUBNET_A="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.0.0/26 --availability-zone "$AZ1" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-public-a},{Key=kubernetes.io/role/elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)"

PUBLIC_SUBNET_B="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.0.64/26 --availability-zone "$AZ2" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-public-b},{Key=kubernetes.io/role/elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)"

APP_SUBNET_A="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "$AZ1" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-app-a},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)"

APP_SUBNET_B="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "$AZ2" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-app-b},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
  --query 'Subnet.SubnetId' --output text)"

DATA_SUBNET_A="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.3.0/25 --availability-zone "$AZ1" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-data-a}]" \
  --query 'Subnet.SubnetId' --output text)"

DATA_SUBNET_B="$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" --cidr-block 10.0.3.128/25 --availability-zone "$AZ2" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-data-b}]" \
  --query 'Subnet.SubnetId' --output text)"

export PUBLIC_SUBNET_A PUBLIC_SUBNET_B APP_SUBNET_A APP_SUBNET_B
export DATA_SUBNET_A DATA_SUBNET_B

# Public subnets assign public IPv4 addresses to launched resources.
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_A" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id "$PUBLIC_SUBNET_B" --map-public-ip-on-launch
```

### 2.2 Route tables y dos NAT Gateways Multi-AZ

Cada zona tiene su propio NAT Gateway para evitar un único punto de salida
privado. Los NAT Gateway se crean en las subredes públicas.

```bash
RT_PUBLIC="$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-public-rt}]" \
  --query 'RouteTable.RouteTableId' --output text)"

RT_APP_A="$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-app-a-rt}]" \
  --query 'RouteTable.RouteTableId' --output text)"

RT_APP_B="$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-app-b-rt}]" \
  --query 'RouteTable.RouteTableId' --output text)"

RT_DATA="$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-data-rt}]" \
  --query 'RouteTable.RouteTableId' --output text)"

aws ec2 create-route --route-table-id "$RT_PUBLIC" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

EIP_A_ALLOC="$(aws ec2 allocate-address --domain vpc \
  --query AllocationId --output text)"
EIP_B_ALLOC="$(aws ec2 allocate-address --domain vpc \
  --query AllocationId --output text)"

NAT_A="$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_A" --allocation-id "$EIP_A_ALLOC" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PROJECT}-nat-a}]" \
  --query 'NatGateway.NatGatewayId' --output text)"

NAT_B="$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_B" --allocation-id "$EIP_B_ALLOC" \
  --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PROJECT}-nat-b}]" \
  --query 'NatGateway.NatGatewayId' --output text)"

aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_A" "$NAT_B"

aws ec2 create-route --route-table-id "$RT_APP_A" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_A"
aws ec2 create-route --route-table-id "$RT_APP_B" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_B"

for subnet in "$PUBLIC_SUBNET_A" "$PUBLIC_SUBNET_B"; do
  aws ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$subnet"
done
aws ec2 associate-route-table --route-table-id "$RT_APP_A" --subnet-id "$APP_SUBNET_A"
aws ec2 associate-route-table --route-table-id "$RT_APP_B" --subnet-id "$APP_SUBNET_B"
aws ec2 associate-route-table --route-table-id "$RT_DATA" --subnet-id "$DATA_SUBNET_A"
aws ec2 associate-route-table --route-table-id "$RT_DATA" --subnet-id "$DATA_SUBNET_B"

export RT_PUBLIC RT_APP_A RT_APP_B RT_DATA NAT_A NAT_B
```

> La tabla explícita `RT_PUBLIC` se asocia a las dos subredes públicas y evita
> depender de la tabla de rutas principal creada por la VPC.

### 2.3 Security Groups encadenados

El tráfico permitido queda encadenado: Internet llega al ALB, el ALB llega a
EKS y únicamente EKS llega a RDS.

```bash
SG_ALB="$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-alb" \
  --description "FreshBox public ALB" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-sg-alb}]" \
  --query GroupId --output text)"

SG_EKS="$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-eks" \
  --description "FreshBox EKS nodes and services" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-sg-eks}]" \
  --query GroupId --output text)"

SG_RDS="$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-rds" \
  --description "FreshBox private RDS" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${PROJECT}-sg-rds}]" \
  --query GroupId --output text)"

aws ec2 authorize-security-group-ingress --group-id "$SG_ALB" \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]},
    {"IpProtocol":"tcp","FromPort":443,"ToPort":443,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}
  ]'

# ALB Controller puede dirigir tráfico HTTP a los servicios EKS.
aws ec2 authorize-security-group-ingress --group-id "$SG_EKS" \
  --source-group "$SG_ALB" --protocol tcp --port 80
for port in 3001 3002 3003 3004; do
  aws ec2 authorize-security-group-ingress --group-id "$SG_EKS" \
    --source-group "$SG_ALB" --protocol tcp --port "$port"
done

# RDS solo acepta MySQL desde EKS.
aws ec2 authorize-security-group-ingress --group-id "$SG_RDS" \
  --source-group "$SG_EKS" --protocol tcp --port 3306

export SG_ALB SG_EKS SG_RDS
```

## 3. Fase 2: persistencia gestionada (Amazon RDS MySQL Multi-AZ)

### 3.1 DB Subnet Group y clave de cifrado

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name "${PROJECT}-db-subnet-group" \
  --db-subnet-group-description "FreshBox private data subnets" \
  --subnet-ids "$DATA_SUBNET_A" "$DATA_SUBNET_B" \
  --tags Key=Name,Value="${PROJECT}-db-subnet-group"

KMS_KEY_ID="$(aws kms create-key \
  --description "FreshBox RDS encryption key" \
  --query KeyMetadata.KeyId --output text)"
export KMS_KEY_ID
```

### 3.2 Crear `freshbox-db`

Define una contraseña temporal solo en la sesión actual. En una operación real
usa AWS Secrets Manager o una contraseña inyectada de forma segura.

```bash
export DB_NAME="freshbox"
export DB_USER="freshbox_admin"
read -r -s -p "Contraseña temporal de RDS: " DB_PASSWORD
echo

aws rds create-db-instance \
  --db-instance-identifier freshbox-db \
  --db-instance-class db.t4g.small \
  --engine mysql \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --kms-key-id "$KMS_KEY_ID" \
  --multi-az \
  --db-name "$DB_NAME" \
  --master-username "$DB_USER" \
  --master-user-password "$DB_PASSWORD" \
  --backup-retention-period 7 \
  --no-publicly-accessible \
  --db-subnet-group-name "${PROJECT}-db-subnet-group" \
  --vpc-security-group-ids "$SG_RDS" \
  --port 3306 \
  --copy-tags-to-snapshot \
  --tags Key=Name,Value=freshbox-db

aws rds wait db-instance-available \
  --db-instance-identifier freshbox-db
```

`--multi-az` crea la instancia standby administrada en otra zona. La consola
de AWS debe mostrar **Multi-AZ: Yes** y **Publicly accessible: No**.

### 3.3 Verificar estado y endpoint

```bash
aws rds describe-db-instances \
  --db-instance-identifier freshbox-db \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port,MultiAZ:MultiAZ,Public:PubliclyAccessible,Class:DBInstanceClass}' \
  --output table

export RDS_ENDPOINT="$(aws rds describe-db-instances \
  --db-instance-identifier freshbox-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)"
printf 'RDS_ENDPOINT=%s\n' "$RDS_ENDPOINT"
```

### 3.4 Inicialización de Base de Datos en Red Privada (Zero-Trust)

La inicialización se realiza desde un Pod cliente efímero dentro de EKS, en
lugar de hacer la instancia RDS pública con `--publicly-accessible`. Esta
decisión:

- evita exponer el puerto `3306` a Internet;
- respeta el encadenamiento de Security Groups
  (`freshbox-sg-rds <- freshbox-sg-eks`), donde RDS solo acepta conexiones
  originadas desde EKS; y
- aprovecha la conectividad intra-VPC entre las subredes privadas de la
  aplicación y de datos.

El Pod `rds-client` se elimina automáticamente con `--rm` después de cada
operación. El script obtiene el endpoint dinámicamente mediante AWS CLI y
canaliza [init.sql](init.sql) al cliente MySQL que se ejecuta dentro del Pod:

```bash
chmod +x scripts/db-init-k8s.sh
./scripts/db-init-k8s.sh
```

También se pueden ejecutar las operaciones manualmente:

```bash
export REGION="us-east-1"
export DB_ENDPOINT="$(aws rds describe-db-instances \
  --db-instance-identifier freshbox-db \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)"
export DB_NAME="freshbox"
export DB_USER="alumno"
export DB_PASS="alumno123"

kubectl run rds-client --rm -i --restart=Never \
  --image=mysql:8.0 \
  --namespace=freshbox \
  --env="MYSQL_PWD=$DB_PASS" \
  -- mysql -h "$DB_ENDPOINT" -u "$DB_USER" "$DB_NAME" < init.sql

kubectl run rds-client --rm -i --restart=Never \
  --image=mysql:8.0 \
  --namespace=freshbox \
  --env="MYSQL_PWD=$DB_PASS" \
  -- mysql -h "$DB_ENDPOINT" -u "$DB_USER" "$DB_NAME" \
  -e "SELECT id, nombre, precio, stock FROM productos;"
```

> El usuario y contraseña solicitados corresponden a la configuración actual
> de la EP2. Para un entorno real, reemplaza estos valores por un secreto
> gestionado y no los almacenes en texto plano.

## 4. Fase 3: pipeline CI/CD a Amazon ECR

El workflow [`.github/workflows/deploy-ecr.yml`](.github/workflows/deploy-ecr.yml)
construye las cinco imágenes para `linux/arm64` usando QEMU y Docker Buildx,
y las publica en ECR:

- `freshbox-frontend`
- `freshbox-get-products`
- `freshbox-create-product`
- `freshbox-update-product`
- `freshbox-delete-product`

Crear los repositorios ECR antes de ejecutar el workflow. El comando es
idempotente: solo crea un repositorio si todavía no existe.

```bash
ECR_REPOSITORIES=(
  freshbox-frontend
  freshbox-get-products
  freshbox-create-product
  freshbox-update-product
  freshbox-delete-product
)

for repository in "${ECR_REPOSITORIES[@]}"; do
  if ! aws ecr describe-repositories \
    --repository-names "$repository" \
    --region "$REGION" >/dev/null 2>&1; then
    aws ecr create-repository \
      --repository-name "$repository" \
      --image-scanning-configuration scanOnPush=true \
      --region "$REGION"
  fi
done
```

Configurar en GitHub: **Settings -> Secrets and variables -> Actions**:

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | `aws_access_key_id` de AWS Details |
| `AWS_SECRET_ACCESS_KEY` | `aws_secret_access_key` de AWS Details |
| `AWS_SESSION_TOKEN` | `aws_session_token` de AWS Details |
| `AWS_REGION` | `us-east-1` |

La sesión del Learner Lab expira aproximadamente a las cuatro horas. Cuando
se renueven las credenciales, actualiza los tres secretos temporales antes de
ejecutar el workflow manualmente o hacer push a `main`.

Para observar o ejecutar el pipeline:

```bash
# Opcional: validar el workflow localmente si act está instalado.
act workflow_dispatch

# El disparo normal ocurre al publicar cambios en main.
git push origin main
```

## 5. Fase 4: clúster Amazon EKS y cargas de trabajo

### 5.1 Configuración declarativa de `cluster.yaml`

Se utiliza `eksctl` con un archivo declarativo porque permite versionar y
reproducir la topología del clúster, las subredes, el grupo de nodos y sus
capacidades sin depender de una secuencia manual en la consola. Además,
`eksctl` coordina la creación de EKS, Managed Node Groups, IAM y CloudFormation
con una única operación auditable.

El archivo [`k8s/cluster.yaml`](k8s/cluster.yaml) define el clúster
`freshbox-cluster` en `us-east-1`, Kubernetes `1.30`, las subredes privadas de
aplicación y las subredes públicas para los balanceadores. Los placeholders
evitan guardar IDs específicos de una sesión del Learner Lab en el repositorio.

#### Instalar `eksctl` en AWS CloudShell

En AWS CloudShell, instala la versión más reciente de `eksctl` para la
arquitectura `amd64`, agrega el binario al `PATH` y verifica que responda:

```bash
# 1. Descargar e instalar eksctl para la arquitectura de CloudShell.
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf "eksctl_$PLATFORM.tar.gz" -C /tmp
rm "eksctl_$PLATFORM.tar.gz"
mkdir -p ~/.local/bin
mv /tmp/eksctl ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc

# 2. Verificar que el comando responda.
eksctl version
```

Ejecuta estos comandos desde la raíz del repositorio para que la ruta del
archivo declarativo sea `k8s/cluster.yaml`. Si CloudShell contiene el archivo
en el directorio actual, también puedes usar `-f cluster.yaml`.

Antes de crear el clúster, resuelve los IDs de la VPC, subredes, Security Group
de EKS y el ARN del rol preexistente `LabRole`:

```bash
export CLUSTER_NAME="freshbox-cluster"
export REGION="us-east-1"
export VPC_ID="${VPC_ID:?Define VPC_ID de la Fase 1}"
export APP_SUBNET_A="${APP_SUBNET_A:?Define APP_SUBNET_A de la Fase 1}"
export APP_SUBNET_B="${APP_SUBNET_B:?Define APP_SUBNET_B de la Fase 1}"
export PUBLIC_SUBNET_A="${PUBLIC_SUBNET_A:?Define PUBLIC_SUBNET_A de la Fase 1}"
export PUBLIC_SUBNET_B="${PUBLIC_SUBNET_B:?Define PUBLIC_SUBNET_B de la Fase 1}"
export SG_EKS="${SG_EKS:?Define SG_EKS de la Fase 1}"
export LAB_ROLE_ARN="$(aws iam get-role \
  --role-name LabRole \
  --query 'Role.Arn' \
  --output text)"

sed -i \
  -e "s#VPC_ID_PLACEHOLDER#$VPC_ID#g" \
  -e "s#APP_SUBNET_A_PLACEHOLDER#$APP_SUBNET_A#g" \
  -e "s#APP_SUBNET_B_PLACEHOLDER#$APP_SUBNET_B#g" \
  -e "s#PUBLIC_SUBNET_A_PLACEHOLDER#$PUBLIC_SUBNET_A#g" \
  -e "s#PUBLIC_SUBNET_B_PLACEHOLDER#$PUBLIC_SUBNET_B#g" \
  -e "s#LAB_ROLE_ARN_PLACEHOLDER#$LAB_ROLE_ARN#g" \
  -e "s#SG_EKS_PLACEHOLDER#$SG_EKS#g" \
  k8s/cluster.yaml

# Aprovisionamiento declarativo exacto del clúster.
# 3. Lanzar la creación del clúster EKS con el archivo cluster.yaml.
eksctl create cluster -f k8s/cluster.yaml

# Alternativa si previamente copiaste k8s/cluster.yaml al directorio actual:
# eksctl create cluster -f cluster.yaml

# Verificación post-creación solicitada.
aws eks describe-cluster \
  --name freshbox-cluster \
  --query "cluster.status" \
  --region us-east-1

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"
```

Los Managed Node Groups con `t4g.small` usan Graviton ARM64. Frente a
instancias x86 equivalentes, ofrecen una relación costo/rendimiento favorable
para cargas de microservicios, reducen el costo operativo del clúster y
presentan un consumo térmico y energético menor. La capacidad deseada es de
2 nodos, con escalamiento administrado entre 2 y 4, y los nodos usan
`privateNetworking: true` para no recibir direcciones públicas.

### 5.2 Preparar y aplicar los manifiestos

Actualizar los placeholders antes de aplicar:

```bash
export ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
export RDS_ENDPOINT="$(aws rds describe-db-instances \
  --db-instance-identifier freshbox-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)"

# Sustituir endpoint e imágenes por los valores de la sesión actual.
sed -i "s#<RDS_ENDPOINT>#$RDS_ENDPOINT#g" k8s/configmap.yaml
sed -i "s#<ACCOUNT_ID>#$ACCOUNT_ID#g" k8s/*.yaml
```

Aplicar namespace, configuración, secreto, deployments y HPA:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml

# secret.yaml debe contener valores Base64 válidos y no debe versionar
# credenciales reales. Generar un secreto de sesión si es necesario:
kubectl -n freshbox create secret generic freshbox-secret \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASS="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/get-products-deployment.yaml
kubectl apply -f k8s/create-product-deployment.yaml
kubectl apply -f k8s/update-product-deployment.yaml
kubectl apply -f k8s/delete-product-deployment.yaml
kubectl apply -f k8s/hpa.yaml
```

### 5.3 AWS Load Balancer Controller vía Helm

El controlador necesita OIDC y permisos IAM. En Learner Lab, `eksctl` puede
crear la política/rol asociado si la cuenta tiene permisos IAM suficientes.

```bash
export CLUSTER_NAME="freshbox-cluster"

eksctl utils associate-iam-oidc-provider \
  --region "$REGION" \
  --cluster "$CLUSTER_NAME" \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --create-namespace \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=5m

kubectl apply -f k8s/ingress.yaml
```

Si la cuenta no permite crear el rol IAM automáticamente, crea previamente
el service account siguiendo la política oficial del controlador y cambia
`serviceAccount.create` a `false`.

### 5.4 Verificación operacional

```bash
kubectl get nodes
kubectl get pods -n freshbox
kubectl get svc -n freshbox
kubectl get ingress -n freshbox
kubectl get hpa -n freshbox

# Vista resumida solicitada para la operación diaria.
kubectl get nodes,pods,svc,ingress,hpa -n freshbox

# Diagnóstico de despliegues y eventos recientes.
kubectl get deployments -n freshbox
kubectl describe ingress -n freshbox
kubectl get events -n freshbox --sort-by=.lastTimestamp
```

El objetivo de la EP2 es tener dos o más nodos `Ready`, diez pods base
(cinco deployments con dos réplicas), un endpoint DNS del ALB y los HPA
activos. Los HPA requieren métricas de recursos disponibles en el clúster.
