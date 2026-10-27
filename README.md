# FreshBox SpA - Modernización Cloud Native (EP2)

FreshBox SpA es una plataforma de comercio electrónico de productos orgánicos
modernizada sobre una arquitectura de microservicios contenerizada en
**Amazon Elastic Kubernetes Service (EKS)**, balanceada mediante **AWS Load
Balancer Controller** y con persistencia relacional en **Amazon RDS MySQL
Multi-AZ**.

## Topología de arquitectura

La solución implementa un desacoplamiento por capas:

1. **Ingress y networking**
   - AWS Load Balancer Controller aprovisiona un Application Load Balancer
     (ALB) público a partir de `k8s/ingress.yaml`.
   - El Ingress enruta `/` al frontend NGINX y `/api/products` al servicio
     `get-products`.
2. **Cómputo en Amazon EKS**
   - Namespace dedicado: `freshbox`.
   - Frontend NGINX para servir archivos estáticos y actuar como proxy interno.
   - Microservicios Node.js separados por operación CRUD:
     - `get-products` en el puerto `3001` para leer el catálogo.
     - `create-product` en el puerto `3002` para insertar productos.
     - `update-product` en el puerto `3003` para modificar productos.
     - `delete-product` en el puerto `3004` para eliminar productos.
   - Los servicios Kubernetes son `ClusterIP` y se comunican mediante DNS
     interno del clúster.
3. **Persistencia**
   - Amazon RDS MySQL `db.t4g.small` en subredes privadas y configuración
     Multi-AZ.
   - El puerto `3306` se restringe mediante Security Groups para aceptar
     conexiones desde EKS.
4. **Registro y entrega**
   - Cinco imágenes publicadas en Amazon ECR para `linux/arm64`.
   - El workflow [`.github/workflows/deploy-ecr.yml`](.github/workflows/deploy-ecr.yml)
     usa QEMU, Docker Buildx y credenciales temporales del Learner Lab.
5. **Observabilidad y escalado**
   - HPA para los cuatro microservicios backend.
   - Métricas de CPU mediante `metrics-server` o el componente equivalente
     habilitado en el clúster.

## Estructura del repositorio

```text
desarrolloappEP2/
├── DEPLOYMENT_RUNBOOK.md
├── README.md
├── init.sql
├── k8s/
│   ├── cluster.yaml
│   ├── configmap.yaml
│   ├── create-product-deployment.yaml
│   ├── delete-product-deployment.yaml
│   ├── frontend-deployment.yaml
│   ├── get-products-deployment.yaml
│   ├── hpa.yaml
│   ├── ingress.yaml
│   ├── namespace.yaml
│   ├── secret.yaml
│   └── update-product-deployment.yaml
├── microservicioEKSFrontend/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── index.html
│   ├── css/styles.css
│   └── js/app.js
├── microserviciosEKSBackend/
│   ├── create-product/
│   ├── delete-product/
│   ├── get-products/
│   └── update-product/
└── scripts/
    ├── db-init-k8s.sh
    ├── ecr-push.sh
    └── guia-docente-ep2.md
```

## Configuración del reverse proxy NGINX

El archivo [microservicioEKSFrontend/nginx.conf](microservicioEKSFrontend/nginx.conf)
configura NGINX dentro del contenedor frontend:

```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location /api/products {
        proxy_pass http://get-products:3001;
        proxy_set_header Host $host;
    }

    location ~ ^/api/products/(\d+)$ {
        if ($request_method = PUT) {
            proxy_pass http://update-product:3003;
        }
        if ($request_method = DELETE) {
            proxy_pass http://delete-product:3004;
        }
        proxy_set_header Host $host;
    }
}
```

El servicio NGINX resuelve los nombres `get-products`, `update-product` y
`delete-product` mediante el DNS interno de Kubernetes. Las operaciones
`POST` de la colección y la configuración completa de headers/proxy deben
validarse contra la versión desplegada de los microservicios antes de una
demostración.

## Variables de entorno de persistencia

| Variable | Valor |
|---|---|
| `DB_HOST` | Endpoint privado de RDS |
| `DB_USER` | Usuario configurado en RDS |
| `DB_PASS` | Contraseña configurada en RDS |
| `DB_NAME` | `freshbox` |
| `DB_PORT` | `3306` |

No publiques credenciales reales en Git. Para la inicialización desde la red
privada del clúster usa [scripts/db-init-k8s.sh](scripts/db-init-k8s.sh), que
ejecuta un cliente MySQL efímero dentro de EKS.

## Despliegue de la infraestructura

La guía ejecutable completa de AWS CLI, VPC, NAT Gateways, RDS, ECR y EKS está
en [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md).

## Despliegue de cargas de trabajo en Kubernetes

### 1. Namespace y configuración

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml

# No versionar credenciales reales. Crear el Secret desde valores de sesión.
kubectl -n freshbox create secret generic freshbox-secret \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASS="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
```

El archivo [k8s/secret.yaml](k8s/secret.yaml) contiene placeholders seguros
para evitar publicar credenciales reales.

### 2. Microservicios y frontend

```bash
kubectl apply -f k8s/get-products-deployment.yaml
kubectl apply -f k8s/create-product-deployment.yaml
kubectl apply -f k8s/update-product-deployment.yaml
kubectl apply -f k8s/delete-product-deployment.yaml
kubectl apply -f k8s/frontend-deployment.yaml
```

### 3. Ingress y Application Load Balancer

```bash
kubectl apply -f k8s/ingress.yaml
kubectl get ingress freshbox-ingress -n freshbox
```

El campo `ADDRESS` del Ingress muestra el DNS público del ALB cuando el
AWS Load Balancer Controller termina de aprovisionarlo.

### 4. Autoescalabilidad

El manifiesto [k8s/hpa.yaml](k8s/hpa.yaml) crea un HPA para cada backend con
un mínimo de 2 réplicas, un máximo de 5 y objetivo de utilización de CPU del
70%:

```bash
kubectl apply -f k8s/hpa.yaml
kubectl get hpa -n freshbox
```

## Pruebas de integración y validación CRUD

| Operación | Método | Endpoint | Servicio destino | Descripción |
|---|---|---|---|---|
| Read | `GET` | `/api/products` | `get-products:3001` | Consulta el catálogo desde RDS |
| Create | `POST` | `/api/products` | `create-product:3002` | Inserta un nuevo producto |
| Update | `PUT` | `/api/products/:id` | `update-product:3003` | Modifica stock o precio |
| Delete | `DELETE` | `/api/products/:id` | `delete-product:3004` | Elimina un producto |

Validar el estado general:

```bash
kubectl get nodes
kubectl get pods -n freshbox
kubectl get svc -n freshbox
kubectl get ingress -n freshbox
kubectl get hpa -n freshbox
```

Desde el DNS del ALB, una prueba de lectura puede ejecutarse así:

```bash
export ALB_DNS="$(kubectl get ingress freshbox-ingress \
  -n freshbox -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
curl --fail --show-error "http://${ALB_DNS}/api/products"
```

## Inicialización de RDS desde EKS

La inicialización mantiene RDS privado y evita exponer `3306` a Internet:

```bash
chmod +x scripts/db-init-k8s.sh
./scripts/db-init-k8s.sh
```

El script obtiene el endpoint mediante AWS CLI, ejecuta `init.sql` desde un
Pod efímero `mysql:8.0` y valida los registros de `productos`.

## Prueba local

Antes de migrar a EKS, valida los microservicios con el entorno local
disponible en la entrega anterior. La ejecución local debe proporcionar las
mismas variables `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` y `DB_PORT`.

---

2026 - Diseñador: Ignacio A. Pastenet M.
