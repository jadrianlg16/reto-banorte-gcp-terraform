package integration

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gcp-datacenter/tests/helpers"
)

// parentResource devuelve dónde crear carpetas de prueba: TERRATEST_FOLDER_ID o la
// organización TERRATEST_ORG_ID (omite la prueba si no hay ninguno).
func parentResource(t *testing.T) string {
	t.Helper()
	folder, org := helpers.ProjectParent(t)
	if folder != "" {
		return "folders/" + folder
	}
	return "organizations/" + org
}

// TestFolders comprueba el módulo folders (§8): una carpeta por entorno pedido, bajo el padre
// dado y con IDs de la forma folders/<número>. No necesita proyecto.
func TestFolders(t *testing.T) {
	t.Parallel()
	parent := parentResource(t)
	run := helpers.NewRun("folders")
	ctx := t.Context()

	opts := helpers.FixtureOptions(t, "folders", map[string]any{
		"parent": parent,
		"prefix": run.Prefix,
	})
	defer helpers.DestroyContextBackground(t, opts)
	terraform.InitAndApplyContext(t, ctx, opts)

	container := terraform.OutputContext(t, ctx, opts, "container_id")
	ids := terraform.OutputMapContext(t, ctx, opts, "ids")
	require.Len(t, ids, 2)

	for _, env := range []string{"dev", "qa"} {
		id, ok := ids[env]
		require.True(t, ok, "falta la carpeta %s", env)
		assert.Regexp(t, `^folders/[0-9]+$`, id)

		f := helpers.GcloudJSON(t, ctx, "resource-manager", "folders", "describe", helpers.FolderNumber(id))
		assert.Equal(t, env, helpers.PathString(f, "displayName"))
		assert.Equal(t, container, helpers.PathString(f, "parent"), "padre de %s", env)
		assert.Equal(t, "ACTIVE", helpers.PathString(f, "state"), "estado de %s", env)
	}
}
