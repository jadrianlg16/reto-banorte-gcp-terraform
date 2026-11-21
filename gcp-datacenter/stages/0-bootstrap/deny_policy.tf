# Política de denegación de IAM sobre la carpeta bootstrap contra la cuenta de 1-org.
#
# 1-org necesita roles/iam.securityAdmin y roles/resourcemanager.folderAdmin en la
# organización (IAM por grupos, carpetas), y por herencia esos roles también cubren la carpeta
# bootstrap, el proyecto semilla, las cuentas de las demás etapas y el bucket de estado. Sin
# esta política, 1-org podría darse permiso para tomar la identidad de las cuentas 2 a 5 o
# ampliar su acceso al bucket. 1-org no necesita nada de eso dentro de esta carpeta: solo
# lee 0-bootstrap/ y escribe 1-org/ en el bucket (permisos de objeto, que no se niegan aquí)
# y usa el proyecto semilla como proyecto de cuota (serviceusage.services.use).
#
# Una denegación se impone sobre cualquier permiso de una política de permisos, venga de
# donde venga (incluso de un rol que 1-org se dé a sí misma en la organización).
#
# Límites conocidos (las políticas de denegación no los cubren):
# - Los permisos de las políticas de denegación (iam.denypolicies.*) no se pueden negar: 1-org
#   podría darse roles/iam.denyAdmin en la organización y borrar esta política. Queda en los
#   registros de actividad administrativa de la organización.
# - Los permisos de objeto de Cloud Storage no se niegan: 1-org los necesita para su propio
#   prefijo, y una condición de denegación solo puede usar etiquetas, no el nombre del objeto.
#   Si 1-org se diera un rol de Storage en la organización, podría leer otros prefijos.
#
# VERIFICAR-EN-APPLY: que la política adjunta a la carpeta también niegue
# folders.setIamPolicy sobre la propia carpeta bootstrap (la documentación solo dice que se
# hereda hacia abajo), y que la API de políticas de denegación (IAM v2) acepte las
# credenciales de usuario de quien corre la etapa 0 sin proyecto de cuota explícito.
resource "google_iam_deny_policy" "bootstrap_folder" {
  parent       = urlencode("cloudresourcemanager.googleapis.com/${module.bootstrap_folder.ids[local.environment]}")
  name         = "${var.prefix}-${local.environment}-sec-deny-1-org"
  display_name = "Protege la carpeta bootstrap de la cuenta de 1-org"

  rules {
    description = "1-org no puede cambiar el IAM ni tomar la identidad de nada dentro de la carpeta bootstrap."
    deny_rule {
      denied_principals = [
        "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.stage["1-org"].email}",
      ]
      denied_permissions = local.bootstrap_denied_permissions
    }
  }
}

locals {
  # Formato de las políticas de denegación: <servicio>.googleapis.com/<recurso>.<verbo>. Todos
  # figuran en la lista de permisos admitidos en políticas de denegación de Google.
  bootstrap_denied_permissions = [
    # Carpeta y proyecto semilla: su IAM, moverlos o borrarlos.
    "cloudresourcemanager.googleapis.com/folders.setIamPolicy",
    "cloudresourcemanager.googleapis.com/folders.move",
    "cloudresourcemanager.googleapis.com/folders.delete",
    "cloudresourcemanager.googleapis.com/projects.setIamPolicy",
    "cloudresourcemanager.googleapis.com/projects.move",
    "cloudresourcemanager.googleapis.com/projects.delete",
    # Cuentas de servicio de las etapas: su IAM y tomar su identidad.
    "iam.googleapis.com/serviceAccounts.setIamPolicy",
    "iam.googleapis.com/serviceAccounts.actAs",
    "iam.googleapis.com/serviceAccounts.getAccessToken",
    "iam.googleapis.com/serviceAccounts.getOpenIdToken",
    "iam.googleapis.com/serviceAccounts.implicitDelegation",
    "iam.googleapis.com/serviceAccounts.signBlob",
    "iam.googleapis.com/serviceAccounts.signJwt",
    "iam.googleapis.com/serviceAccounts.update",
    "iam.googleapis.com/serviceAccounts.delete",
    "iam.googleapis.com/serviceAccounts.disable",
    "iam.googleapis.com/serviceAccountKeys.create",
    # Bucket de estado: su IAM, configuración o borrado.
    "storage.googleapis.com/buckets.setIamPolicy",
    "storage.googleapis.com/buckets.update",
    "storage.googleapis.com/buckets.delete",
    "storage.googleapis.com/managedFolders.setIamPolicy",
    "storage.googleapis.com/objects.setIamPolicy",
    # Llave del estado: su IAM, cambiarla o destruir versiones.
    "cloudkms.googleapis.com/keyRings.setIamPolicy",
    "cloudkms.googleapis.com/cryptoKeys.setIamPolicy",
    "cloudkms.googleapis.com/cryptoKeys.update",
    "cloudkms.googleapis.com/cryptoKeyVersions.destroy",
  ]
}
