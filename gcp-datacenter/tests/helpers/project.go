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

// ProjectParent devuelve dónde se crean los proyectos y carpetas efímeros: TERRATEST_FOLDER_ID
// si está definido; si no, la organización TERRATEST_ORG_ID. Omite la prueba si no hay ninguno.
func ProjectParent(t testing.TB) (folderNumber, orgNumber string) {
	t.Helper()
	if f := Getenv(EnvFolderID, ""); f != "" {
		return FolderNumber(f), ""
	}
	env := RequireEnv(t, EnvOrgID)
	return "", OrgNumber(env[EnvOrgID])
}

// RequireProjectEnv omite la prueba temprano (antes de copiar archivos) si no hay con qué
// obtener un proyecto de prueba.
func RequireProjectEnv(t testing.TB) {
	t.Helper()
	if IsTrue(EnvReuseProject) {
		RequireEnv(t, EnvProjectID)
		return
	}
	RequireEnv(t, EnvBillingAccount)
	ProjectParent(t)
}

// NewTestProject devuelve el proyecto de la prueba y registra su limpieza con t.Cleanup.
//
//   - Por defecto (como en CI) crea un proyecto efímero "tt-<módulo>-<id>" con
//     TERRATEST_BILLING_ACCOUNT, en TERRATEST_FOLDER_ID o, si no está, en la organización
//     TERRATEST_ORG_ID (contrato §9.2: un proyecto efímero por módulo). Al final lo borra
//     (deletion_policy = "DELETE": queda 30 días en DELETE_REQUESTED).
//   - Con TEST_REUSE_PROJECT=true reutiliza TERRATEST_PROJECT_ID: solo habilita las APIs (sin
//     deshabilitarlas al terminar). Los nombres siguen siendo únicos por el prefijo de la
//     ejecución.
func NewTestProject(t *testing.T, run Run, apis []string) TestProject {
	t.Helper()
	ctx := t.Context()
	RequireProjectEnv(t)

	reuse := IsTrue(EnvReuseProject)
	vars := map[string]any{
		"apis":   apis,
		"labels": RequiredLabels("dev", run),
	}
	if reuse {
		vars["create_project"] = false
		vars["project_id"] = Getenv(EnvProjectID, "")
	} else {
		folder, org := ProjectParent(t)
		vars["create_project"] = true
		vars["project_id"] = run.ProjectID()
		vars["folder_id"] = folder
		vars["org_id"] = org
		vars["billing_account"] = Getenv(EnvBillingAccount, "")
	}

	opts := FixtureOptions(t, "support/project", vars)
	// El proyecto se destruye después de los defer de la prueba (que destruyen el fixture del
	// módulo dentro de él): t.Cleanup corre al final.
	DestroyOnCleanup(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	return TestProject{
		ID:        terraform.OutputContext(t, ctx, opts, "project_id"),
		Number:    terraform.OutputContext(t, ctx, opts, "project_number"),
		Ephemeral: !reuse,
	}
}

// DestroyContextBackground destruye opts con un contexto nuevo; para usar en defer, así el
// destroy corre aunque el contexto de la prueba se haya cancelado.
func DestroyContextBackground(t testing.TB, opts *terraform.Options) {
	t.Helper()
	terraform.DestroyContext(t, context.Background(), opts)
}
