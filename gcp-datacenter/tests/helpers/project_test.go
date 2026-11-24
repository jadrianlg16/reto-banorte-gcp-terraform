package helpers

import (
	"fmt"
	"runtime"
	"strings"
	"testing"
)

// Pruebas sin GCP de la guarda del proyecto de pruebas (TERRATEST_LANDING_ZONE_PROJECT_ID).

func TestLandingZoneConflict(t *testing.T) {
	cases := []struct {
		name, test, landing string
		conflict            bool
	}{
		{"iguales", "bnt-lz-pruebas", "bnt-lz-pruebas", true},
		{"mayúsculas y espacios", " BNT-lz-pruebas ", "bnt-lz-pruebas", true},
		{"distintos", "bnt-terratest", "bnt-lz-pruebas", false},
		{"sin proyecto de la landing zone", "bnt-terratest", "", false},
		{"sin proyecto de pruebas", "", "bnt-lz-pruebas", false},
		{"ninguno", "", "", false},
	}
	for _, c := range cases {
		err := LandingZoneConflict(c.test, c.landing)
		if (err != nil) != c.conflict {
			t.Errorf("%s: LandingZoneConflict(%q, %q) = %v, se esperaba conflicto %v", c.name, c.test, c.landing, err, c.conflict)
		}
		if err != nil && (strings.Contains(err.Error(), "bnt-lz-pruebas") || strings.Contains(err.Error(), "BNT")) {
			t.Errorf("%s: el mensaje muestra el ID del proyecto: %v", c.name, err)
		}
	}
}

// guardRecorder es un testing.TB que anota Fatal y Skipf en vez de terminar la prueba real.
type guardRecorder struct {
	testing.TB
	fatal, skipped bool
	msg            string
}

func (r *guardRecorder) Helper() {}

func (r *guardRecorder) Fatal(args ...any) {
	r.fatal, r.msg = true, fmt.Sprint(args...)
	runtime.Goexit()
}

func (r *guardRecorder) Skipf(format string, args ...any) {
	r.skipped, r.msg = true, fmt.Sprintf(format, args...)
	runtime.Goexit()
}

func runRequireProjectEnv(t *testing.T) *guardRecorder {
	r := &guardRecorder{TB: t}
	done := make(chan struct{})
	go func() {
		defer close(done)
		RequireProjectEnv(r)
	}()
	<-done
	return r
}

func TestRequireProjectEnvLandingZone(t *testing.T) {
	cases := []struct {
		name                   string
		test, landing, ephem   string
		billing, folder        string
		wantFatal, wantSkipped bool
	}{
		{name: "mismo proyecto: error", test: "bnt-lz-pruebas", landing: "bnt-lz-pruebas", wantFatal: true},
		{name: "mismo proyecto con proyectos efímeros: error", test: "bnt-lz-pruebas", landing: "bnt-lz-pruebas",
			ephem: "true", billing: "000000-000000-000000", folder: "123", wantFatal: true},
		{name: "otro proyecto: corre", test: "bnt-terratest", landing: "bnt-lz-pruebas"},
		{name: "sin la variable de la landing zone: corre", test: "bnt-terratest"},
		{name: "sin proyecto de pruebas: se omite, no es error", landing: "bnt-lz-pruebas", wantSkipped: true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv(EnvProjectID, c.test)
			t.Setenv(EnvLandingZoneProjectID, c.landing)
			t.Setenv(EnvEphemeralProjects, c.ephem)
			t.Setenv(EnvBillingAccount, c.billing)
			t.Setenv(EnvFolderID, c.folder)
			r := runRequireProjectEnv(t)
			if r.fatal != c.wantFatal || r.skipped != c.wantSkipped {
				t.Errorf("fatal=%v skipped=%v (%q), se esperaba fatal=%v skipped=%v", r.fatal, r.skipped, r.msg, c.wantFatal, c.wantSkipped)
			}
			if r.fatal && strings.Contains(r.msg, "bnt-lz-pruebas") {
				t.Errorf("el mensaje muestra el ID del proyecto: %q", r.msg)
			}
		})
	}
}

func TestRequireOrganization(t *testing.T) {
	run := func(t *testing.T) *guardRecorder {
		r := &guardRecorder{TB: t}
		done := make(chan struct{})
		go func() {
			defer close(done)
			RequireOrganization(r, "TestOrg")
		}()
		<-done
		return r
	}
	t.Run("sin organización: se omite con la marca", func(t *testing.T) {
		t.Setenv(EnvOrgID, " ")
		r := run(t)
		if !r.skipped || !strings.Contains(r.msg, OrgSkipMarker) || !strings.Contains(r.msg, "se omite") {
			t.Errorf("skipped=%v msg=%q: se esperaba una omisión con %s y \"se omite\" (go-test-report.sh)", r.skipped, r.msg, OrgSkipMarker)
		}
	})
	t.Run("con organización: sigue", func(t *testing.T) {
		t.Setenv(EnvOrgID, "123456789012")
		if r := run(t); r.skipped || r.fatal {
			t.Errorf("con %s definido no debe omitirse: %q", EnvOrgID, r.msg)
		}
	})
	if strings.ContainsAny(OrgSkipMarker, "<>&") {
		t.Errorf("OrgSkipMarker %q lleva caracteres que go test -json escapa", OrgSkipMarker)
	}
}

func TestIntegrationLabelsAreNotAnEnvironment(t *testing.T) {
	labels := RequiredLabels(TestEnvLabel, Run{ID: "x"})
	for _, env := range []string{"dev", "qa", "prod", "common", "bootstrap"} {
		if labels["env"] == env {
			t.Errorf("las pruebas de integración etiquetan env=%s, que es un entorno de la landing zone", env)
		}
	}
	for _, k := range RequiredLabelKeys {
		if labels[k] == "" {
			t.Errorf("falta la etiqueta obligatoria %s", k)
		}
	}
}
