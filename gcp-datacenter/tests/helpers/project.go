package helpers

import (
	"context"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// TestProject es el proyecto donde una prueba de integración crea lo que necesita.
type TestProject struct {
	ID     string
	Number string
	// Ephemeral es true si la prueba creó el proyecto (y lo borra al terminar).
	Ephemeral bool
}

// ProjectParent devuelve dónde se crean los proyectos efímeros y las carpetas de prueba:
// TERRATEST_FOLDER_ID si está definido; si no, la organización TERRATEST_ORG_ID. Omite la
// prueba si no hay ninguno. Solo lo usan el modo de proyectos efímeros y las pruebas de
// módulos de organización o carpetas.
func ProjectParent(t testing.TB) (folderNumber, orgNumber string) {
	t.Helper()
	if f := Getenv(EnvFolderID, ""); f != "" {
		return FolderNumber(f), ""
	}
	env := RequireEnv(t, EnvOrgID)
	return "", OrgNumber(env[EnvOrgID])
}

// RequireProjectEnv omite la prueba temprano (antes de copiar archivos) si no hay con qué
// obtener un proyecto de prueba: TERRATEST_PROJECT_ID o, con TEST_EPHEMERAL_PROJECTS=true, la
// cuenta de facturación y una carpeta u organización.
func RequireProjectEnv(t testing.TB) {
	t.Helper()
	if !IsTrue(EnvEphemeralProjects) {
		RequireEnv(t, EnvProjectID)
		return
	}
	RequireEnv(t, EnvBillingAccount)
	ProjectParent(t)
}

// NewTestProject devuelve el proyecto de la prueba y registra su limpieza con t.Cleanup.
//
//   - Por defecto (ADR 0029: un solo proyecto, sin carpetas ni organización) usa el proyecto
//     único de pruebas TERRATEST_PROJECT_ID: solo habilita las APIs (sin deshabilitarlas al
//     terminar). Los nombres son únicos por el prefijo de la ejecución, así que varias pruebas
//     pueden correr a la vez en el mismo proyecto. VERIFICAR-EN-APPLY: que las cuotas del
//     proyecto (redes, routers, IP) alcancen para las pruebas en paralelo (go test -parallel,
//     por defecto el número de CPU).
//   - Con TEST_EPHEMERAL_PROJECTS=true crea un proyecto efímero "tt-<módulo>-<id>" con
//     TERRATEST_BILLING_ACCOUNT, en TERRATEST_FOLDER_ID o, si no está, en la organización
//     TERRATEST_ORG_ID (contrato §9.2). Al final lo borra (deletion_policy = "DELETE": queda 30
//     días en DELETE_REQUESTED). HYPOTHESIS: sin organización, una cuenta de servicio no puede
//     crear proyectos; por eso no es el modo por defecto.
func NewTestProject(t *testing.T, run Run, apis []string) TestProject {
	t.Helper()
	ctx := t.Context()
	RequireProjectEnv(t)

	ephemeral := IsTrue(EnvEphemeralProjects)
	vars := map[string]any{
		"apis":   apis,
		"labels": RequiredLabels("dev", run),
	}
	if ephemeral {
		folder, org := ProjectParent(t)
		vars["create_project"] = true
		vars["project_id"] = run.ProjectID()
		vars["folder_id"] = folder
		vars["org_id"] = org
		vars["billing_account"] = Getenv(EnvBillingAccount, "")
	} else {
		vars["create_project"] = false
		vars["project_id"] = Getenv(EnvProjectID, "")
	}

	opts := FixtureOptions(t, "support/project", vars)
	// El proyecto se destruye después de los defer de la prueba (que destruyen el fixture del
	// módulo dentro de él): t.Cleanup corre al final. En el proyecto único solo "destruye" las
	// APIs del estado del fixture, sin apagarlas (disable_on_destroy = false).
	DestroyOnCleanup(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	return TestProject{
		ID:        terraform.OutputContext(t, ctx, opts, "project_id"),
		Number:    terraform.OutputContext(t, ctx, opts, "project_number"),
		Ephemeral: ephemeral,
	}
}

// DestroyContextBackground destruye opts con un contexto nuevo; para usar en defer, así el
// destroy corre aunque el contexto de la prueba se haya cancelado.
func DestroyContextBackground(t testing.TB, opts *terraform.Options) {
	t.Helper()
	terraform.DestroyContext(t, context.Background(), opts)
}
