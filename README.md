# Reto Banorte: Datacenter en GCP con Terraform

Proyecto integrador de *Implementación de redes de área amplia y servicios distribuidos*
(TC3003B, grupo 502), Tec de Monterrey. Socio formador: Banorte. Equipo 2.

El reto es construir un datacenter virtual en Google Cloud Platform gobernado al 100 % como
código: una landing zone hub-and-spoke con entornos de desarrollo, pruebas y producción,
desplegable desde cero con Terraform y un pipeline de CI/CD.

## Contenido

| Carpeta | Contenido |
|---|---|
| `labs/ejercicio-1` | Ejercicio 1: archivo con `local_file`, ciclo init/plan/apply e idempotencia |
| `labs/ejercicio-2` | Ejercicio 2: tres archivos con `for_each` y dependencias con `random_pet` |
| `entregas/fase-1-2` | Actividad Fases 1 y 2: reporte, bitácora del equipo y evidencias de los laboratorios |

## Requisitos

- Terraform ≥ 1.9 (Windows: `winget install Hashicorp.Terraform`; macOS: `brew install hashicorp/tap/terraform`)
- Git

Los laboratorios usan los proveedores `hashicorp/local` y `hashicorp/random`, así que no
necesitan cuenta en ninguna nube.

## Correr los laboratorios

Ejercicio 1:

```bash
cd labs/ejercicio-1
terraform init
terraform plan
terraform apply
terraform plan -var="mensaje=Adiós"   # solo plan: muestra el reemplazo
terraform apply                       # sin cambios: idempotencia
terraform destroy
```

Ejercicio 2:

```bash
cd labs/ejercicio-2
terraform init
terraform plan
terraform apply
terraform state list
# quitar "db" de toset([...]) en main.tf y volver a correr:
terraform plan
terraform destroy
```

Las diapositivas del socio formador escriben los archivos en `/root/` (laboratorio Linux de
KodeKloud). Aquí se usa `${path.module}/` para que el mismo código funcione en Windows y macOS.

En Windows PowerShell 5.1, pon entre comillas los argumentos con punto
(`terraform plan "-var-file=archivo.tfvars"`) y pasa las listas en un archivo `.tfvars`, no con `-var`.
