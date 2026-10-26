# Contenido completo del proyecto `desarrolloappEP2`

Documento unificado para compartir el proyecto con asistentes que no pueden acceder directamente al repositorio.

## Estructura del proyecto

```text
desarrolloappEP2/
  k8s/
    configmap.yaml
    create-product-deployment.yaml
    delete-product-deployment.yaml
    frontend-deployment.yaml
    get-products-deployment.yaml
    hpa.yaml
    ingress.yaml
    namespace.yaml
    secret.yaml
    update-product-deployment.yaml
  microservicioEKSFrontend/
    css/
      styles.css
    js/
      app.js
    Dockerfile
    index.html
    nginx.conf
  microserviciosEKSBackend/
    create-product/
      Dockerfile
      index.js
      package.json
    delete-product/
      Dockerfile
      index.js
      package.json
    get-products/
      Dockerfile
      index.js
      package.json
    update-product/
      Dockerfile
      index.js
      package.json
  scripts/
    ecr-push.sh
    guia-docente-ep2.md
  init.sql
  README.md
```

## Contenido de los archivos

### 1. `init.sql`

Archivo: `init.sql`

````sql
-- FreshBox SpA - Base de Datos para RDS MySQL (EP2)
CREATE DATABASE IF NOT EXISTS freshbox;
USE freshbox;

CREATE TABLE IF NOT EXISTS productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    descripcion TEXT,
    precio DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    categoria VARCHAR(100),
    imagen_url VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO productos (nombre, descripcion, precio, stock, categoria) VALUES
('Manzana organica 1kg', 'Manzanas rojas organicas, cultivo sin pesticidas', 3490.00, 120, 'Frutas'),
('Lechuga hidroponica', 'Lechuga fresca cultivada en sistema hidroponico', 1990.00, 80, 'Verduras'),
('Granola artesanal 500g', 'Granola con avena, miel, almendras y arandanos', 4990.00, 60, 'Snacks'),
('Jugo natural naranja 1L', 'Jugo 100% natural de naranja, sin preservantes', 2990.00, 100, 'Bebidas'),
('Mix frutos secos 250g', 'Mezcla de almendras, nueces, castanas y pasas organicas', 5490.00, 45, 'Snacks');

-- 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 2. `k8s/configmap.yaml`

Archivo: `k8s/configmap.yaml`

````yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: freshbox-config
  namespace: freshbox
data:
  DB_HOST: "<RDS_ENDPOINT>"
  DB_NAME: "freshbox"
  DB_PORT: "3306"

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 3. `k8s/create-product-deployment.yaml`

Archivo: `k8s/create-product-deployment.yaml`

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: create-product
  namespace: freshbox
spec:
  replicas: 2
  selector:
    matchLabels:
      app: create-product
  template:
    metadata:
      labels:
        app: create-product
    spec:
      containers:
      - name: create-product
        image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/freshbox-create-product:latest
        ports:
        - containerPort: 3002
        env:
        - name: PORT
          value: "3002"
        - name: DB_HOST
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_HOST } }
        - name: DB_NAME
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_NAME } }
        - name: DB_PORT
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_PORT } }
        - name: DB_USER
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_USER } }
        - name: DB_PASS
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_PASS } }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: create-product
  namespace: freshbox
spec:
  selector:
    app: create-product
  ports:
  - port: 3002
    targetPort: 3002
  type: ClusterIP

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 4. `k8s/delete-product-deployment.yaml`

Archivo: `k8s/delete-product-deployment.yaml`

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: delete-product
  namespace: freshbox
spec:
  replicas: 2
  selector:
    matchLabels:
      app: delete-product
  template:
    metadata:
      labels:
        app: delete-product
    spec:
      containers:
      - name: delete-product
        image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/freshbox-delete-product:latest
        ports:
        - containerPort: 3004
        env:
        - name: PORT
          value: "3004"
        - name: DB_HOST
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_HOST } }
        - name: DB_NAME
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_NAME } }
        - name: DB_PORT
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_PORT } }
        - name: DB_USER
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_USER } }
        - name: DB_PASS
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_PASS } }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: delete-product
  namespace: freshbox
spec:
  selector:
    app: delete-product
  ports:
  - port: 3004
    targetPort: 3004
  type: ClusterIP

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 5. `k8s/frontend-deployment.yaml`

Archivo: `k8s/frontend-deployment.yaml`

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: freshbox
spec:
  replicas: 2
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
        image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/freshbox-frontend:latest
        ports:
        - containerPort: 80
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: freshbox
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 6. `k8s/get-products-deployment.yaml`

Archivo: `k8s/get-products-deployment.yaml`

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: get-products
  namespace: freshbox
spec:
  replicas: 2
  selector:
    matchLabels:
      app: get-products
  template:
    metadata:
      labels:
        app: get-products
    spec:
      containers:
      - name: get-products
        image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/freshbox-get-products:latest
        ports:
        - containerPort: 3001
        env:
        - name: PORT
          value: "3001"
        - name: DB_HOST
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_HOST } }
        - name: DB_NAME
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_NAME } }
        - name: DB_PORT
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_PORT } }
        - name: DB_USER
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_USER } }
        - name: DB_PASS
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_PASS } }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: get-products
  namespace: freshbox
spec:
  selector:
    app: get-products
  ports:
  - port: 3001
    targetPort: 3001
  type: ClusterIP

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 7. `k8s/hpa.yaml`

Archivo: `k8s/hpa.yaml`

````yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: get-products-hpa
  namespace: freshbox
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: get-products
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: create-product-hpa
  namespace: freshbox
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: create-product
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: update-product-hpa
  namespace: freshbox
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: update-product
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: delete-product-hpa
  namespace: freshbox
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: delete-product
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 8. `k8s/ingress.yaml`

Archivo: `k8s/ingress.yaml`

````yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: freshbox-ingress
  namespace: freshbox
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /api/products
        pathType: Prefix
        backend:
          service:
            name: get-products
            port:
              number: 3001
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 9. `k8s/namespace.yaml`

Archivo: `k8s/namespace.yaml`

````yaml
apiVersion: v1
kind: Namespace
metadata:
  name: freshbox
  labels:
    app: freshbox

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 10. `k8s/secret.yaml`

Archivo: `k8s/secret.yaml`

````yaml
apiVersion: v1
kind: Secret
metadata:
  name: freshbox-secret
  namespace: freshbox
type: Opaque
data:
  # Base64 placeholders; replace before deploying.
  DB_USER: UkVQTEFDRV9NRQ==
  DB_PASS: UkVQTEFDRV9NRQ==

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 11. `k8s/update-product-deployment.yaml`

Archivo: `k8s/update-product-deployment.yaml`

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: update-product
  namespace: freshbox
spec:
  replicas: 2
  selector:
    matchLabels:
      app: update-product
  template:
    metadata:
      labels:
        app: update-product
    spec:
      containers:
      - name: update-product
        image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/freshbox-update-product:latest
        ports:
        - containerPort: 3003
        env:
        - name: PORT
          value: "3003"
        - name: DB_HOST
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_HOST } }
        - name: DB_NAME
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_NAME } }
        - name: DB_PORT
          valueFrom: { configMapKeyRef: { name: freshbox-config, key: DB_PORT } }
        - name: DB_USER
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_USER } }
        - name: DB_PASS
          valueFrom: { secretKeyRef: { name: freshbox-secret, key: DB_PASS } }
        resources:
          requests: { cpu: 100m, memory: 128Mi }
          limits: { cpu: 250m, memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata:
  name: update-product
  namespace: freshbox
spec:
  selector:
    app: update-product
  ports:
  - port: 3003
    targetPort: 3003
  type: ClusterIP

# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 12. `microservicioEKSFrontend/css/styles.css`

Archivo: `microservicioEKSFrontend/css/styles.css`

````css
/* FreshBox SpA - Estilos CSS - EP2 EKS */
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', Tahoma, sans-serif; background: #f0f7f0; color: #333; line-height: 1.6; }
header { background: #2d6a4f; color: white; padding: 20px; text-align: center; }
header h1 { font-size: 2em; }
main { max-width: 1200px; margin: 20px auto; padding: 0 20px; }
section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
h2 { color: #2d6a4f; margin-bottom: 15px; border-bottom: 2px solid #52b788; padding-bottom: 8px; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
th { background: #52b788; color: white; }
button { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; margin: 2px; }
#btn-cargar { background: #52b788; color: white; }
#btn-guardar { background: #2d6a4f; color: white; }
.btn-editar { background: #f39c12; color: white; }
.btn-eliminar { background: #e74c3c; color: white; }
.form-group { margin-bottom: 12px; }
.form-group label { display: block; margin-bottom: 4px; font-weight: 600; }
.form-group input, .form-group textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
.form-actions { margin-top: 15px; }
#mensaje { margin-top: 10px; padding: 8px; border-radius: 4px; }
.mensaje-exito { background: #d4edda; color: #155724; }
.mensaje-error { background: #f8d7da; color: #721c24; }
footer { text-align: center; padding: 15px; background: #2d6a4f; color: white; margin-top: 30px; }
/* 2026 - Disenador asignatura: Ignacio A. Pastenet M. */
````

### 13. `microservicioEKSFrontend/Dockerfile`

Archivo: `microservicioEKSFrontend/Dockerfile`

````dockerfile
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/
COPY css/ /usr/share/nginx/html/css/
COPY js/ /usr/share/nginx/html/js/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 14. `microservicioEKSFrontend/index.html`

Archivo: `microservicioEKSFrontend/index.html`

````html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FreshBox - Productos Organicos (EKS)</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 100 100%27><text y=%27.9em%27 font-size=%2790%27>&#x1F34E;</text></svg>">
    <link rel="stylesheet" href="css/styles.css">
</head>
<body>
    <header><h1>FreshBox SpA</h1><p>Catalogo Online Productos Organicos - EP2 EKS + RDS Multi-AZ</p></header>
    <main>
        <section id="productos-section">
            <h2>Listado de Productos</h2>
            <button id="btn-cargar" onclick="cargarProductos()">Cargar productos</button>
            <table id="tabla-productos"><thead><tr><th>ID</th><th>Nombre</th><th>Descripcion</th><th>Precio</th><th>Stock</th><th>Categoria</th><th>Acciones</th></tr></thead><tbody id="productos-body"></tbody></table>
        </section>
        <section id="formulario-section">
            <h2 id="form-titulo">Nuevo Producto</h2>
            <form id="producto-form" onsubmit="guardarProducto(event)">
                <input type="hidden" id="producto-id">
                <div class="form-group"><label>Nombre:</label><input type="text" id="nombre" required></div>
                <div class="form-group"><label>Descripcion:</label><textarea id="descripcion" rows="2"></textarea></div>
                <div class="form-group"><label>Precio ($):</label><input type="number" id="precio" min="1" step="10" required></div>
                <div class="form-group"><label>Stock:</label><input type="number" id="stock" min="0" required></div>
                <div class="form-group"><label>Categoria:</label><input type="text" id="categoria"></div>
                <div class="form-actions"><button type="submit" id="btn-guardar">Guardar</button><button type="button" onclick="cancelarEdicion()">Cancelar</button></div>
            </form>
            <p id="mensaje"></p>
        </section>
    </main>
    <footer><p>FreshBox SpA - EP2 ARY1102 Arquitectura Cloud - DuocUC 2026 | Dise&#241;ador asignatura: Ignacio A. Pastenet M.</p></footer>
    <script src="js/app.js"></script>
</body>
</html>
````

### 15. `microservicioEKSFrontend/js/app.js`

Archivo: `microservicioEKSFrontend/js/app.js`

````javascript
// FreshBox SpA - Frontend CRUD - EP2 EKS
const API_BASE = window.location.origin;
const API_GET = API_BASE + '/api/products';

document.addEventListener('DOMContentLoaded', cargarProductos);

async function cargarProductos() {
    try {
        const response = await fetch(API_GET);
        const productos = await response.json();
        renderizarTabla(productos);
        mostrarMensaje('Productos cargados', 'exito');
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

function renderizarTabla(productos) {
    const tbody = document.getElementById('productos-body');
    tbody.innerHTML = '';
    if (productos.length === 0) { tbody.innerHTML = '<tr><td colspan="7">No hay productos</td></tr>'; return; }
    productos.forEach(p => {
        const tr = document.createElement('tr');
        tr.innerHTML = `<td>${p.id}</td><td>${p.nombre}</td><td>${p.descripcion || '-'}</td><td>$${Number(p.precio).toLocaleString('es-CL')}</td><td>${p.stock}</td><td>${p.categoria || '-'}</td><td><button class="btn-editar" onclick="editarProducto(${p.id},'${escapar(p.nombre)}','${escapar(p.descripcion||'')}',${p.precio},${p.stock},'${escapar(p.categoria||'')}')">Editar</button> <button class="btn-eliminar" onclick="eliminarProducto(${p.id})">Eliminar</button></td>`;
        tbody.appendChild(tr);
    });
}

async function guardarProducto(event) {
    event.preventDefault();
    const id = document.getElementById('producto-id').value;
    const datos = { nombre: document.getElementById('nombre').value, descripcion: document.getElementById('descripcion').value, precio: parseFloat(document.getElementById('precio').value), stock: parseInt(document.getElementById('stock').value), categoria: document.getElementById('categoria').value };
    try {
        let response;
        if (id) { response = await fetch(API_GET + '/' + id, { method: 'PUT', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        else { response = await fetch(API_GET, { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(datos) }); }
        if (!response.ok) throw new Error('Error');
        mostrarMensaje(id ? 'Modificado' : 'Creado', 'exito');
        limpiarFormulario(); cargarProductos();
    } catch (error) { mostrarMensaje('Error: ' + error.message, 'error'); }
}

async function eliminarProducto(id) {
    if (!confirm('Eliminar?')) return;
    await fetch(API_GET + '/' + id, { method: 'DELETE' });
    mostrarMensaje('Eliminado', 'exito'); cargarProductos();
}

function editarProducto(id, n, d, p, s, c) { document.getElementById('producto-id').value=id; document.getElementById('nombre').value=n; document.getElementById('descripcion').value=d; document.getElementById('precio').value=p; document.getElementById('stock').value=s; document.getElementById('categoria').value=c; document.getElementById('form-titulo').textContent='Editar (ID:'+id+')'; }
function cancelarEdicion() { limpiarFormulario(); }
function limpiarFormulario() { document.getElementById('producto-form').reset(); document.getElementById('producto-id').value=''; document.getElementById('form-titulo').textContent='Nuevo Producto'; }
function mostrarMensaje(t, tipo) { const m=document.getElementById('mensaje'); m.textContent=t; m.className=tipo==='exito'?'mensaje-exito':'mensaje-error'; setTimeout(()=>{m.textContent='';m.className='';},4000); }
function escapar(s) { return s.replace(/'/g,"\\'"); }
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 16. `microservicioEKSFrontend/nginx.conf`

Archivo: `microservicioEKSFrontend/nginx.conf`

````text
server {
    listen 80;
    server_name localhost;
    location / { root /usr/share/nginx/html; index index.html; }
    location /api/products { proxy_pass http://get-products:3001; proxy_set_header Host $host; }
    location ~ ^/api/products/(\d+)$ {
        if ($request_method = PUT) { proxy_pass http://update-product:3003; }
        if ($request_method = DELETE) { proxy_pass http://delete-product:3004; }
        proxy_set_header Host $host;
    }
}
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 17. `microserviciosEKSBackend/create-product/Dockerfile`

Archivo: `microserviciosEKSBackend/create-product/Dockerfile`

````dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
EXPOSE 3002
CMD ["node", "index.js"]
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 18. `microserviciosEKSBackend/create-product/index.js`

Archivo: `microserviciosEKSBackend/create-product/index.js`

````javascript
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const PORT = process.env.PORT || 3002;
const dbConfig = { host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER || 'alumno', password: process.env.DB_PASS || 'alumno123', database: process.env.DB_NAME || 'freshbox', port: process.env.DB_PORT || 3306 };

app.post('/api/products', async (req, res) => {
  try {
    const { nombre, descripcion, precio, stock, categoria } = req.body;
    if (!nombre || !precio || stock === undefined) return res.status(400).json({ error: 'Campos obligatorios: nombre, precio, stock' });
    if (precio <= 0) return res.status(400).json({ error: 'El precio debe ser mayor a 0' });
    const conn = await mysql.createConnection(dbConfig);
    const [result] = await conn.execute('INSERT INTO productos (nombre, descripcion, precio, stock, categoria) VALUES (?, ?, ?, ?, ?)', [nombre, descripcion || null, precio, stock, categoria || null]);
    const [newProduct] = await conn.execute('SELECT * FROM productos WHERE id = ?', [result.insertId]);
    await conn.end();
    res.status(201).json(newProduct[0]);
  } catch (error) { res.status(500).json({ error: 'Error al crear producto', detalle: error.message }); }
});

app.get('/health', (req, res) => res.json({ status: 'OK', service: 'create-product', port: PORT }));
app.listen(PORT, () => console.log(`[create-product] Puerto ${PORT}`));
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 19. `microserviciosEKSBackend/create-product/package.json`

Archivo: `microserviciosEKSBackend/create-product/package.json`

````json
{ "name": "freshbox-create-product", "version": "1.0.0", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.18.2", "mysql2": "^3.6.0", "cors": "^2.8.5" } }
````

### 20. `microserviciosEKSBackend/delete-product/Dockerfile`

Archivo: `microserviciosEKSBackend/delete-product/Dockerfile`

````dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
EXPOSE 3004
CMD ["node", "index.js"]
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 21. `microserviciosEKSBackend/delete-product/index.js`

Archivo: `microserviciosEKSBackend/delete-product/index.js`

````javascript
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const PORT = process.env.PORT || 3004;
const dbConfig = { host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER || 'alumno', password: process.env.DB_PASS || 'alumno123', database: process.env.DB_NAME || 'freshbox', port: process.env.DB_PORT || 3306 };

app.delete('/api/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const conn = await mysql.createConnection(dbConfig);
    const [existing] = await conn.execute('SELECT * FROM productos WHERE id = ?', [id]);
    if (existing.length === 0) { await conn.end(); return res.status(404).json({ error: 'Producto no encontrado' }); }
    await conn.execute('DELETE FROM productos WHERE id = ?', [id]);
    await conn.end();
    res.json({ message: 'Producto eliminado correctamente', id: parseInt(id) });
  } catch (error) { res.status(500).json({ error: 'Error al eliminar producto', detalle: error.message }); }
});

app.get('/health', (req, res) => res.json({ status: 'OK', service: 'delete-product', port: PORT }));
app.listen(PORT, () => console.log(`[delete-product] Puerto ${PORT}`));
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 22. `microserviciosEKSBackend/delete-product/package.json`

Archivo: `microserviciosEKSBackend/delete-product/package.json`

````json
{ "name": "freshbox-delete-product", "version": "1.0.0", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.18.2", "mysql2": "^3.6.0", "cors": "^2.8.5" } }
````

### 23. `microserviciosEKSBackend/get-products/Dockerfile`

Archivo: `microserviciosEKSBackend/get-products/Dockerfile`

````dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
EXPOSE 3001
CMD ["node", "index.js"]
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 24. `microserviciosEKSBackend/get-products/index.js`

Archivo: `microserviciosEKSBackend/get-products/index.js`

````javascript
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const PORT = process.env.PORT || 3001;
const dbConfig = { host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER || 'alumno', password: process.env.DB_PASS || 'alumno123', database: process.env.DB_NAME || 'freshbox', port: process.env.DB_PORT || 3306 };

app.get('/api/products', async (req, res) => {
  try {
    const conn = await mysql.createConnection(dbConfig);
    const [rows] = await conn.execute('SELECT * FROM productos ORDER BY id DESC');
    await conn.end();
    res.json(rows);
  } catch (error) { res.status(500).json({ error: 'Error al consultar productos', detalle: error.message }); }
});

app.get('/api/products/:id', async (req, res) => {
  try {
    const conn = await mysql.createConnection(dbConfig);
    const [rows] = await conn.execute('SELECT * FROM productos WHERE id = ?', [req.params.id]);
    await conn.end();
    if (rows.length === 0) return res.status(404).json({ error: 'Producto no encontrado' });
    res.json(rows[0]);
  } catch (error) { res.status(500).json({ error: 'Error', detalle: error.message }); }
});

app.get('/health', (req, res) => res.json({ status: 'OK', service: 'get-products', port: PORT }));
app.listen(PORT, () => console.log(`[get-products] Puerto ${PORT}`));

// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 25. `microserviciosEKSBackend/get-products/package.json`

Archivo: `microserviciosEKSBackend/get-products/package.json`

````json
{ "name": "freshbox-get-products", "version": "1.0.0", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.18.2", "mysql2": "^3.6.0", "cors": "^2.8.5" } }
````

### 26. `microserviciosEKSBackend/update-product/Dockerfile`

Archivo: `microserviciosEKSBackend/update-product/Dockerfile`

````dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY index.js .
EXPOSE 3003
CMD ["node", "index.js"]
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 27. `microserviciosEKSBackend/update-product/index.js`

Archivo: `microserviciosEKSBackend/update-product/index.js`

````javascript
const express = require('express');
const mysql = require('mysql2/promise');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const PORT = process.env.PORT || 3003;
const dbConfig = { host: process.env.DB_HOST || 'localhost', user: process.env.DB_USER || 'alumno', password: process.env.DB_PASS || 'alumno123', database: process.env.DB_NAME || 'freshbox', port: process.env.DB_PORT || 3306 };

app.put('/api/products/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { nombre, descripcion, precio, stock, categoria } = req.body;
    if (!nombre || !precio || stock === undefined) return res.status(400).json({ error: 'Campos obligatorios: nombre, precio, stock' });
    const conn = await mysql.createConnection(dbConfig);
    const [existing] = await conn.execute('SELECT * FROM productos WHERE id = ?', [id]);
    if (existing.length === 0) { await conn.end(); return res.status(404).json({ error: 'Producto no encontrado' }); }
    await conn.execute('UPDATE productos SET nombre = ?, descripcion = ?, precio = ?, stock = ?, categoria = ? WHERE id = ?', [nombre, descripcion || null, precio, stock, categoria || null, id]);
    const [updated] = await conn.execute('SELECT * FROM productos WHERE id = ?', [id]);
    await conn.end();
    res.json(updated[0]);
  } catch (error) { res.status(500).json({ error: 'Error al modificar producto', detalle: error.message }); }
});

app.get('/health', (req, res) => res.json({ status: 'OK', service: 'update-product', port: PORT }));
app.listen(PORT, () => console.log(`[update-product] Puerto ${PORT}`));
// 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 28. `microserviciosEKSBackend/update-product/package.json`

Archivo: `microserviciosEKSBackend/update-product/package.json`

````json
{ "name": "freshbox-update-product", "version": "1.0.0", "main": "index.js", "scripts": { "start": "node index.js" }, "dependencies": { "express": "^4.18.2", "mysql2": "^3.6.0", "cors": "^2.8.5" } }
````

### 29. `README.md`

Archivo: `README.md`

````markdown
# FreshBox SpA â€” Migracion a EKS + RDS Multi-AZ (EP2)

## Descripcion

Migracion de FreshBox desde EC2+Docker (EP1) hacia Amazon EKS (5 pods) y RDS MySQL Multi-AZ. Misma funcionalidad CRUD, plataforma gestionada con orquestacion.

## Arquitectura EP2

| Capa | Componente | Servicio AWS |
|------|-----------|--------------|
| Publica | ALB Ingress | ALB (creado por Ingress Controller) |
| Privada APP | EKS Cluster + Node Group | t4g.small, 2-4 nodos Multi-AZ |
| Privada APP | 5 Deployments x 2 replicas | 10 pods |
| Privada DATA | RDS MySQL Multi-AZ | db.t4g.small, failover automatico |
| Registro | 5 imagenes | ECR |
| Observabilidad | Container Insights | CloudWatch |

## Estructura

```
desarrolloappEP2/
â”œâ”€â”€ README.md
â”œâ”€â”€ init.sql                        (BD freshbox para RDS)
â”œâ”€â”€ microserviciosEKSBackend/
â”‚   â”œâ”€â”€ get-products/  (Dockerfile, index.js, package.json)
â”‚   â”œâ”€â”€ create-product/
â”‚   â”œâ”€â”€ update-product/
â”‚   â””â”€â”€ delete-product/
â”œâ”€â”€ microservicioEKSFrontend/
â”‚   â”œâ”€â”€ Dockerfile
â”‚   â”œâ”€â”€ nginx.conf
â”‚   â”œâ”€â”€ index.html
â”‚   â”œâ”€â”€ css/styles.css
â”‚   â””â”€â”€ js/app.js
â”œâ”€â”€ k8s/
â”‚   â”œâ”€â”€ namespace.yaml
â”‚   â”œâ”€â”€ configmap.yaml
â”‚   â”œâ”€â”€ secret.yaml
â”‚   â”œâ”€â”€ frontend-deployment.yaml
â”‚   â”œâ”€â”€ get-products-deployment.yaml
â”‚   â”œâ”€â”€ create-product-deployment.yaml
â”‚   â”œâ”€â”€ update-product-deployment.yaml
â”‚   â”œâ”€â”€ delete-product-deployment.yaml
â”‚   â”œâ”€â”€ ingress.yaml
â”‚   â””â”€â”€ hpa.yaml
â””â”€â”€ scripts/
    â”œâ”€â”€ ecr-push.sh
    â””â”€â”€ guia-docente-ep2.md
```

## Nota importante

El desarrollo es **autocontenido**: incluye todos los microservicios, frontend, manifiestos K8s y scripts necesarios para implementar sin depender de otra carpeta.

## Variables de Entorno

| Variable | Valor |
|----------|-------|
| DB_HOST | (RDS endpoint) |
| DB_USER | alumno |
| DB_PASS | alumno123 |
| DB_NAME | freshbox |
| DB_PORT | 3306 |

## Prueba local

Usar el docker-compose.yml de EP1 para validar que la app funciona antes de migrar a EKS.

---

2026 - Disenador: Ignacio A. Pastenet M.
````

### 30. `scripts/ecr-push.sh`

Archivo: `scripts/ecr-push.sh`

````bash
#!/bin/bash
# FreshBox SpA - Build y Push imagenes a ECR (EP2 - EKS)
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

REPOS=("freshbox-frontend" "freshbox-get-products" "freshbox-create-product" "freshbox-update-product" "freshbox-delete-product")
for REPO in "${REPOS[@]}"; do aws ecr create-repository --repository-name $REPO --region $REGION 2>/dev/null || true; done

docker build --platform linux/arm64 -t freshbox-frontend ./microservicioEKSFrontend
docker build --platform linux/arm64 -t freshbox-get-products ./microserviciosEKSBackend/get-products
docker build --platform linux/arm64 -t freshbox-create-product ./microserviciosEKSBackend/create-product
docker build --platform linux/arm64 -t freshbox-update-product ./microserviciosEKSBackend/update-product
docker build --platform linux/arm64 -t freshbox-delete-product ./microserviciosEKSBackend/delete-product

for REPO in "${REPOS[@]}"; do
    docker tag $REPO $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
    docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:latest
done
echo "=== Push EP2 completado ==="
# 2026 - Disenador asignatura: Ignacio A. Pastenet M.
````

### 31. `scripts/guia-docente-ep2.md`

Archivo: `scripts/guia-docente-ep2.md`

````markdown
# Guia Docente â€” Implementacion EP2 (FreshBox SpA - EKS)

## Referencia para el docente â€” NO entregar al estudiante

| Campo | Valor |
|-------|-------|
| Caso | FreshBox SpA - Migracion a EKS + RDS Multi-AZ |
| Cluster | freshbox-cluster |
| Namespace | freshbox |
| Nodos | t4g.small, 2-4 Multi-AZ |
| RDS | db.t4g.small MySQL Multi-AZ |

---

## Pasos esperados

1. Crear/reutilizar VPC Multi-AZ (misma EP1 o nueva)
2. Crear Security Groups (SG-ALB, SG-EKS, SG-RDS)
3. Crear RDS MySQL Multi-AZ + ejecutar init.sql
4. Crear cluster EKS con eksctl (o consola)
5. Configurar kubectl
6. Reutilizar imagenes ECR de EP1 (o rebuild + push)
7. Actualizar manifiestos (ACCOUNT_ID, RDS_ENDPOINT)
8. kubectl apply (namespace, configmap, secret, deployments, services)
9. Instalar ALB Controller + aplicar ingress
10. Aplicar HPA
11. Habilitar Container Insights (si el lab lo permite, sino omitir)
12. Validar CRUD via ALB DNS

## Criterios de evaluacion

| Aspecto | Verificar |
|---------|-----------|
| EKS cluster activo | eksctl get cluster â†’ ACTIVE |
| 2+ nodos Ready | kubectl get nodes |
| 10 pods Running | kubectl get pods -n freshbox (5x2) |
| RDS Multi-AZ | Consola RDS â†’ Multi-AZ: Yes |
| ALB Ingress | kubectl get ingress â†’ ADDRESS con DNS |
| HPA activo | kubectl get hpa -n freshbox |
| CRUD funcional | GET, POST, PUT, DELETE via ALB |
| Container Insights | CloudWatch â†’ metricas por pod (si el lab lo permite, sino omitir y documentar teoricamente) |
| Seguridad | SG encadenados, cifrado RDS |

---

2026 - Disenador: Ignacio A. Pastenet M.
````
