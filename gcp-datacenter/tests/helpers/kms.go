package helpers

import (
	"context"
	"testing"
)

// MaxRotationSeconds es la rotación máxima que admite el contrato: 90 días (§7.2, política 6).
const MaxRotationSeconds int64 = 90 * 24 * 60 * 60

// DestroyKeyVersions programa la destrucción de todas las versiones habilitadas de una llave
// de KMS. Las llaves y los llaveros no se pueden borrar en GCP; tras sacar del estado una
// llave con prevent_destroy (módulo kms), esto evita que siga cobrando en un proyecto
// reutilizado (TEST_PROJECT_ID). En un proyecto efímero sobra, pero no estorba.
func DestroyKeyVersions(t testing.TB, ctx context.Context, keyID string) {
	t.Helper()
	var versions []map[string]any
	if err := GcloudJSONE(t, ctx, &versions, "kms", "keys", "versions", "list", "--key="+keyID, "--filter=state=ENABLED"); err != nil {
		t.Errorf("no se pudieron listar las versiones de %s: %v", keyID, err)
		return
	}
	for _, v := range versions {
		name := PathString(v, "name")
		if name == "" {
			continue
		}
		if _, err := GcloudE(t, ctx, "kms", "keys", "versions", "destroy", name); err != nil {
			t.Errorf("no se pudo programar la destrucción de %s: %v", name, err)
		}
	}
}

// AssertKeyRotation comprueba en la API que la llave rota cada 90 días o menos y tiene la
// próxima rotación programada (política 6 de §9.1).
func AssertKeyRotation(t testing.TB, ctx context.Context, keyID string) {
	t.Helper()
	key := GcloudJSON(t, ctx, "kms", "keys", "describe", keyID)
	period := PathString(key, "rotationPeriod")
	secs, err := ParseSeconds(period)
	if err != nil {
		t.Errorf("%s: rotationPeriod %q no es una duración: %v", keyID, period, err)
		return
	}
	if secs <= 0 || secs > MaxRotationSeconds {
		t.Errorf("%s: rotación %ds fuera de (0, %d]", keyID, secs, MaxRotationSeconds)
	}
	if PathString(key, "nextRotationTime") == "" {
		t.Errorf("%s: sin nextRotationTime", keyID)
	}
	if got := PathString(key, "purpose"); got != "ENCRYPT_DECRYPT" {
		t.Errorf("%s: purpose = %q, se esperaba ENCRYPT_DECRYPT", keyID, got)
	}
}
