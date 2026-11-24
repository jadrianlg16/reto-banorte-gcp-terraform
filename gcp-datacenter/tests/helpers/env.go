// Package helpers reúne lo que comparten las pruebas de integración y la de extremo a
// extremo: lectura de variables de entorno, compuertas de costo, nombres únicos, etiquetas
// obligatorias, opciones de Terraform con errores reintentables y consultas a GCP.
//
// Ningún identificador de organización, proyecto, cuenta de facturación ni correo vive en el
// código: todo llega por variables de entorno (ver tests/README.md).
package helpers

import (
	"os"
	"sort"
	"strings"
	"testing"
)

// Variables de entorno que leen las pruebas. Las TERRATEST_* y GOOGLE_CLOUD_PROJECT son las que
// exporta .github/workflows/terratest.yml (mismos nombres que las variables de repositorio); las
// TEST_* son compuertas y ajustes que el flujo toma de variables de repositorio con el mismo
// nombre.
const (
	// EnvProjectID es el proyecto único de pruebas (ADR 0029: un solo proyecto, sin carpetas):
	// cada prueba de integración crea ahí sus recursos con un prefijo propio de la ejecución.
	// Conviene que no sea el proyecto de la landing zone: drift.yml reportaría los recursos de
	// prueba como no administrados.
	EnvProjectID    = "TERRATEST_PROJECT_ID"
	EnvQuotaProject = "GOOGLE_CLOUD_PROJECT" // proyecto por defecto de gcloud y del proveedor
	// EnvLandingZoneProjectID es el proyecto de la landing zone (GCP_TFVARS_JSON.common.project_id;
	// terratest.yml lo exporta con scripts/terratest-project-check.py). Si está definido y es
	// igual a TERRATEST_PROJECT_ID, RequireProjectEnv detiene la prueba con un error.
	EnvLandingZoneProjectID = "TERRATEST_LANDING_ZONE_PROJECT_ID"
	// EnvEphemeralProjects = "true" vuelve al modo de un proyecto efímero por prueba (contrato
	// §9.2): necesita TERRATEST_BILLING_ACCOUNT y una carpeta u organización donde crearlo.
	EnvEphemeralProjects = "TEST_EPHEMERAL_PROJECTS"
	EnvBillingAccount    = "TERRATEST_BILLING_ACCOUNT" // XXXXXX-XXXXXX-XXXXXX, solo con proyectos efímeros
	EnvFolderID          = "TERRATEST_FOLDER_ID"       // opcional: carpeta de los proyectos efímeros
	EnvOrgID             = "TERRATEST_ORG_ID"          // número de la organización, sin "organizations/"; proyectos efímeros y pruebas que solo valen con organización (org, vpc-sc)
	EnvRegion            = "TEST_REGION"               // región primaria (por defecto us-central1)
	EnvDRRegion          = "TEST_DR_REGION"            // región secundaria (por defecto us-east4)
	EnvAllowExpensive    = "TEST_ALLOW_EXPENSIVE"      // "true" habilita las pruebas lentas o caras
	EnvAllowOrg          = "TEST_ALLOW_ORG"            // "true" habilita las pruebas con alcance de organización
	EnvDirectoryCust     = "TEST_DIRECTORY_CUSTOMER_ID"
	EnvAccessPolicyID    = "TEST_ACCESS_POLICY_ID" // política de Access Context Manager existente
	EnvNotificationMail  = "TEST_NOTIFICATION_EMAIL"
	EnvGKESecurityGroup  = "TEST_GKE_SECURITY_GROUP" // gke-security-groups@<dominio>
	EnvMIGImage          = "TEST_MIG_IMAGE"
	EnvCloudRunImage     = "TEST_CLOUD_RUN_IMAGE"
	EnvLBDomain          = "TEST_LB_DOMAIN"
)

// Valores por defecto que no identifican a nadie: son las regiones del ADR 0002 e imágenes
// públicas de Google.
//
// DefaultCloudRunImage y Binary Authorization: las pruebas de integración corren en un proyecto
// de pruebas sin google_binary_authorization_policy, cuya política es la de Google por defecto
// (admite todo), así que la imagen pública sirve. En la prueba de extremo a extremo, 1-base crea
// la única política del proyecto (su regla por defecto admite los repositorios del proyecto y
// binary_authorization_allowlist_patterns, ADR 0029 §4): e2e/config.example.json agrega esta
// imagen a binary_authorization_allowlist_patterns de 1-base. Quien cambie
// TEST_CLOUD_RUN_IMAGE o cloud_run_image debe cambiar también ese patrón.
// VERIFICAR-EN-APPLY: que el patrón con * final admita la etiqueta :latest.
const (
	DefaultRegion        = "us-central1"
	DefaultDRRegion      = "us-east4"
	DefaultMIGImage      = "projects/debian-cloud/global/images/family/debian-12"
	DefaultCloudRunImage = "us-docker.pkg.dev/cloudrun/container/hello:latest"
)

// Getenv devuelve la variable de entorno name o def si está vacía.
func Getenv(name, def string) string {
	if v := strings.TrimSpace(os.Getenv(name)); v != "" {
		return v
	}
	return def
}

// IsTrue indica si la variable de entorno name vale "true" (sin distinguir mayúsculas).
func IsTrue(name string) bool {
	return strings.EqualFold(strings.TrimSpace(os.Getenv(name)), "true")
}

// RequireEnv devuelve los valores de las variables pedidas. Si falta alguna, omite la prueba
// con un mensaje que las nombra todas, para que se configuren de una vez.
func RequireEnv(t testing.TB, names ...string) map[string]string {
	t.Helper()
	values := make(map[string]string, len(names))
	var missing []string
	for _, n := range names {
		v := Getenv(n, "")
		if v == "" {
			missing = append(missing, n)
			continue
		}
		values[n] = v
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		t.Skipf("se omite: faltan variables de entorno %s (ver tests/README.md)", strings.Join(missing, ", "))
	}
	return values
}

// RequireGate omite la prueba si la compuerta gate no vale "true". reason dice por qué la
// prueba está detrás de la compuerta (costo, tiempo o alcance de organización).
func RequireGate(t testing.TB, gate, reason string) {
	t.Helper()
	if !IsTrue(gate) {
		t.Skipf("se omite: %s; exporta %s=true para correrla (ver tests/README.md)", reason, gate)
	}
}

// RequireExpensive omite la prueba salvo que TEST_ALLOW_EXPENSIVE=true.
func RequireExpensive(t testing.TB, what string) {
	t.Helper()
	RequireGate(t, EnvAllowExpensive, what+" es lenta o cara")
}

// RequireOrgScope omite la prueba salvo que TEST_ALLOW_ORG=true.
func RequireOrgScope(t testing.TB, what string) {
	t.Helper()
	RequireGate(t, EnvAllowOrg, what+" crea recursos con alcance de organización")
}

// Region devuelve la región primaria de las pruebas.
func Region() string { return Getenv(EnvRegion, DefaultRegion) }

// DRRegion devuelve la región secundaria de las pruebas.
func DRRegion() string { return Getenv(EnvDRRegion, DefaultDRRegion) }

// FolderNumber devuelve solo el número de una carpeta ("folders/123" o "123" → "123").
func FolderNumber(id string) string {
	return strings.TrimPrefix(strings.TrimSpace(id), "folders/")
}

// OrgNumber devuelve solo el número de una organización.
func OrgNumber(id string) string {
	return strings.TrimPrefix(strings.TrimSpace(id), "organizations/")
}
