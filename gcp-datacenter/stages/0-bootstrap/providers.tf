# La etapa 0 la corre una sola vez una persona administradora con sus credenciales de
# aplicación (gcloud auth application-default login). Todavía no existe el proyecto semilla,
# así que no hay proyecto de cuota que fijar; las etapas 1 a 5 sí lo fijan (billing_project).
provider "google" {}

provider "google-beta" {}
