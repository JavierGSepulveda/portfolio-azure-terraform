# Portafolio: Infraestructura Azure con Terraform

Segundo proyecto de un portafolio de tres, construido para demostrar el mismo patrón de infraestructura ya implementado en AWS, esta vez sobre Azure — usando la misma herramienta (Terraform) para validar que el conocimiento adquirido es de conceptos, no de un proveedor específico.

## Qué incluye

- Resource Group + Virtual Network con subred pública y subred privada
- Máquina Virtual Linux (Ubuntu 24.04 LTS) sirviendo una página web con nginx
- Network Security Group con acceso restringido (HTTP público, SSH solo desde una IP específica)
- Storage Account + Blob Container privado para assets estáticos
- Todo definido como código con Terraform, cero recursos creados a mano desde el portal

## Arquitectura

```
                        Internet
                            │
                 (ruta de salida implícita
                  de toda VNet de Azure)
                            │
                    ┌───────┴────────┐
                    │  Resource Group: portfolio-rg
                    │  Región: Chile Central
                    │
                    │  VNet (10.0.0.0/16)
                    │
                    │  ┌──────────────────────┐
                    │  │ Subred pública         │
                    │  │ 10.0.1.0/24            │
                    │  │                        │
                    │  │  [VM + nginx]          │
                    │  │   + Public IP (Static) │
                    │  │  NSG asociado:         │
                    │  │   - HTTP (80) abierto  │
                    │  │   - SSH (22) solo mi IP│
                    │  └──────────────────────┘
                    │
                    │  ┌──────────────────────┐
                    │  │ Subred privada         │
                    │  │ 10.0.2.0/24            │
                    │  │ (sin recursos,         │
                    │  │  sin Public IP)        │
                    │  └──────────────────────┘
                    └────────────────┘

        [Storage Account privado] — servicio separado, fuera de la VNet
        └── Blob Container "static-assets" (privado)
```

## Decisiones arquitectónicas y por qué

### Región: Chile Central
Elegida por cercanía real a mi ubicación (Santiago), en vez de una región genérica de EE.UU. La suscripción Azure for Students tiene una lista personalizada de ~5 regiones permitidas (impuesta por una política de Azure Policy específica de este tipo de cuenta, verificable en Policy → Assignments → "Allowed locations"); Chile Central estaba entre ellas.

### Sin Internet Gateway (a diferencia de AWS)
Esta es la diferencia conceptual más importante entre ambos proyectos: en AWS, una VPC nace sin salida a internet hasta crear explícitamente un Internet Gateway y una tabla de rutas. En Azure, **toda VNet ya tiene una ruta de sistema hacia internet por defecto** para tráfico saliente — no existe un recurso equivalente que crear. Lo que Azure sí controla explícitamente es la entrada: un recurso solo es alcanzable desde internet si se le asigna una **Public IP** directamente (en este proyecto, a la NIC de la VM). La distinción "pública/privada" no vive en la subred ni en su tabla de rutas, como en AWS, sino en si el recurso individual tiene o no una IP pública — Azure no impone ni verifica esta convención, es responsabilidad del desarrollador mantenerla.

### Network Security Group (NSG) en vez de Security Group + NACL
Azure fusiona en un solo tipo de recurso lo que en AWS son dos conceptos separados. El NSG de este proyecto se asoció a nivel de subred (como una NACL) con reglas de `Allow` explícitas para los puertos 80 y 22, usando `priority` para el orden de evaluación (a diferencia de AWS, donde el orden no importa en Security Groups). No se declaró ninguna regla de salida explícita: Azure permite todo el tráfico saliente por defecto (`AllowVnetOutBound`/`AllowInternetOutBound`), justo lo opuesto al comportamiento por defecto de AWS.

### Sin HTTPS (puerto 443)
Misma razón que en el proyecto de AWS: un certificado SSL/TLS válido y gratuito requiere un dominio propio apuntando al servidor, lo cual queda fuera del alcance de este proyecto de portafolio.

### Tamaño de VM: Standard_B2ats_v2 (no fue una elección de preferencia)
El tamaño final fue determinado por restricciones reales de capacidad de la plataforma, no por diseño — ver la bitácora de troubleshooting más abajo para el detalle completo. Se verificó su disponibilidad real (sin restricciones) con `az vm list-skus` antes de usarlo.

### Storage Account con bloqueo de acceso público explícito
`allow_nested_items_to_be_public = false` a nivel de cuenta, más `container_access_type = "private"` a nivel del contenedor — misma filosofía de seguridad en capas que el bloqueo de acceso público del bucket S3 en el proyecto de AWS, adaptada a la jerarquía de dos niveles de Azure (Storage Account → Blob Container).

### `resource_provider_registrations = "none"` en el provider
Por defecto, el provider de Azure intenta registrar automáticamente unos 68 Resource Providers en la suscripción, incluyendo muchos que este proyecto no usa — proceso lento que puede colgarse indefinidamente en suscripciones nuevas. Se desactivó ese comportamiento y se registraron manualmente solo los tres necesarios (`Microsoft.Network`, `Microsoft.Compute`, `Microsoft.Storage`).

### Cuenta: Azure for Students
Se usó esta modalidad en vez de la cuenta gratuita estándar de Azure porque no exige tarjeta de crédito (se verifica con correo institucional), reduciendo la fricción y el riesgo dado un presupuesto personal ajustado. Otorga USD $100 de crédito.

## Bitácora de troubleshooting real

Este proyecto tuvo significativamente más fricción real con la plataforma que el de AWS — documentado aquí en detalle porque es el material más valioso para explicar en una entrevista.

| Qué pasó | Causa real | Cómo se resolvió |
|---|---|---|
| `terraform plan` se quedaba colgado indefinidamente, sin error | El provider de Azure intenta registrar ~68 Resource Providers automáticamente en suscripciones nuevas; algunos quedaron atascados tras una cancelación previa con Ctrl+C | Se agregó `resource_provider_registrations = "none"` al provider y se registraron manualmente solo los 3 providers necesarios vía `az provider register` |
| `SkuNotAvailable` al crear la VM con `Standard_B1s` en Chile Central | Restricción de capacidad física del datacenter para ese tamaño específico en ese momento (no relacionado a cuota ni configuración) | Se investigó disponibilidad real con `az vm list-skus --location <region> --all` antes de seguir adivinando tamaños |
| `RequestDisallowedByAzure` al intentar cambiar a la región Brazil South | Las suscripciones Azure for Students tienen una lista personalizada y restringida de regiones permitidas (~5), distinta para cada cuenta, impuesta por una política de Azure Policy | Se consultó la lista real en el portal (Policy → Assignments → "Allowed locations") en vez de asumir una región "segura" |
| Error 404 `ResourceNotFound` esperando el estado de aprovisionamiento de la VNet, inmediatamente después de crear el Resource Group | Consistencia eventual de la API de Azure: el recurso existe pero la API aún no lo refleja al releerlo | Se resolvió reintentando `terraform apply` — Terraform es idempotente y solo intenta crear lo que falta |
| `Provider produced inconsistent result after apply` al crear la subred pública | Bug de consistencia eventual conocido y reportado en el repositorio oficial de HashiCorp, no exclusivo de este recurso | Reintento del `apply` |
| `a resource with the ID "..." already exists - needs to be imported` para Public IP y subred pública | Los recursos sí se habían creado en Azure en el intento fallido anterior, pero el error impidió que Terraform lo registrara en el `tfstate` — quedaron huérfanos | `terraform import` de cada recurso usando el ID exacto que Azure entregó en el mensaje de error |
| Casi todos los tamaños de VM económicos (`B`, `D`, `E`, `F` básicos) mostraban `NotAvailableForSubscription` en `eastus` | Patrón de restricción de capacidad generalizado, no aislado a un solo tamaño — confirmado como un problema conocido y reportado por otros usuarios de Azure for Students en foros oficiales de Microsoft | Se usó `az vm list-usage` para distinguir restricción de **capacidad** (momentánea) de restricción de **cuota** (estructural); se confirmó cuota real disponible para las familias `BS` y `DSv3` |
| `OperationNotAllowed... Cores quota` al probar un tamaño de la familia `NVadsV710v5` | Se seleccionó por error un tamaño de VM con GPU desde una tabla larga de resultados; las cuentas estudiantiles tienen cuota 0 por defecto para familias GPU | Se evitaron familias especializadas (GPU, memoria alta, cómputo alto) y se volvió a familias de propósito general con cuota confirmada |
| `Provider produced inconsistent result` / 404 al crear ambas subredes en paralelo | Azure API rechaza modificaciones concurrentes a la misma VNet cuando se crean varias subredes al mismo tiempo | Se forzó creación secuencial con `depends_on = [azurerm_subnet.public]` en la subred privada |
| Advertencia de deprecación en `azurerm_storage_container`, argumento `storage_account_name` | Azure migró este recurso al nuevo argumento `storage_account_id` | Se actualizó al argumento nuevo, confirmado como disponible desde la versión 4.9.0 del provider |
| VS Code sugirió (vía Quick Fix) actualizar también `azurerm_storage_blob` a `storage_account_id`/`storage_container_id`, generando el error "Unexpected attribute" | Inconsistencia real y confirmada del provider: `azurerm_storage_container` ya migró a argumentos por ID, pero `azurerm_storage_blob` **todavía no** los soporta (confirmado en la documentación oficial vigente) | Se revirtió únicamente el bloque del blob a los argumentos con `_name`, dejando el del contenedor con `_id` |

## Comparación rápida: AWS vs Azure (mismo proyecto, dos nubes)

| Concepto | AWS | Azure |
|---|---|---|
| Contenedor de red | VPC | Virtual Network (VNet) |
| Agrupación lógica de recursos | No existe un equivalente directo | Resource Group (obligatorio) |
| Salida a internet | Requiere Internet Gateway + tabla de rutas | Incluida por defecto en toda VNet |
| Qué define "público" | Tabla de rutas de la subred | Si el recurso tiene una Public IP asignada |
| Firewall | Security Group (por instancia) + NACL (por subred), por separado | Network Security Group (NSG), un solo recurso para ambos niveles |
| Egress por defecto | Bloqueado (hay que abrirlo) | Permitido |
| Script de arranque | `user_data` (texto plano) | `custom_data` (base64) |
| Llave SSH | Recurso separado (`aws_key_pair`) | Argumento inline dentro de la VM |
| Almacenamiento de objetos | Bucket S3 (un solo nivel) | Storage Account + Blob Container (dos niveles) |
| Nombres únicos globalmente | Sí (buckets S3) | Sí, más estricto (Storage Accounts: solo minúsculas y números, sin guiones) |

## Cómo ejecutar este proyecto

### Prerrequisitos
- Cuenta de Azure (recomendado: Azure for Students si eres elegible)
- Azure CLI instalado y autenticado (`az login`)
- Terraform instalado
- **Importante:** verifica tus propias regiones permitidas antes de definir `location` (Policy → Assignments → "Allowed locations" en el portal de Azure) — pueden ser distintas a las usadas en este proyecto

### Pasos

```powershell
git clone https://github.com/JavierGSepulveda/azure-terraform-portfolio.git
cd azure-terraform-portfolio
terraform init
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Storage
terraform plan
terraform apply
```

Genera tu propia llave SSH antes del `apply` si no existe:
```powershell
ssh-keygen -t rsa -b 2048 -f portfolio-azure-key
```

Al terminar, verifica con la IP del output:
```powershell
Invoke-WebRequest -Uri "http://<vm_public_ip>"
```

### Destruir al terminar

```powershell
terraform destroy
```

Este proyecto no mantiene infraestructura corriendo de forma permanente — mismo criterio que el proyecto de AWS, para no arriesgar el crédito de la cuenta.

## Estructura del proyecto

```
azure-terraform-portfolio/
├── providers.tf        # Providers azurerm (~>4.0) y random (~>3.0)
├── variables.tf          # (reservado para valores configurables)
├── main.tf                # Resource Group, VNet, subredes, NSG, VM, Storage
├── outputs.tf              # IP pública de la VM, nombre del Storage Account
├── custom_data.sh           # Script de arranque (instala nginx vía apt)
├── assets/hello.txt          # Archivo de prueba subido al Storage Account
├── .gitignore
└── README.md
```

## Posibles mejoras futuras (fuera de alcance de este proyecto)

- Distribuir recursos en Availability Zones para alta disponibilidad
- Backend remoto de Terraform usando un Storage Account dedicado
- HTTPS con dominio propio
- Manejo automatizado de reintentos ante los bugs de consistencia eventual documentados arriba (por ejemplo, con `-retry` a nivel de script de CI/CD)

## Autor

Javier Sepúlveda — segundo proyecto de un portafolio de tres, construido como parte de un proceso de aprendizaje autónomo en infraestructura como código multicloud.
