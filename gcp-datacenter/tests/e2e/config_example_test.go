package e2e

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"gcp-datacenter/tests/helpers"
)

// binauthzPatternMatches aplica un patrón de admission_whitelist_patterns a una imagen:
// "**" final cubre cualquier resto; "*" final, un resto sin "/"; sin comodín, la ruta exacta con
// cualquier etiqueta o digest. HIPÓTESIS sobre la semántica de Binary Authorization (documentación
// de Google; VERIFICAR-EN-APPLY): el patrón del ejemplo usa "*" final, que cubre las dos lecturas.
func binauthzPatternMatches(pattern, image string) bool {
	switch {
	case strings.HasSuffix(pattern, "**"):
		return strings.HasPrefix(image, strings.TrimSuffix(pattern, "**"))
	case strings.HasSuffix(pattern, "*"):
		prefix := strings.TrimSuffix(pattern, "*")
		return strings.HasPrefix(image, prefix) && !strings.Contains(strings.TrimPrefix(image, prefix), "/")
	default:
		path := image
		if i := strings.IndexAny(path, "@"); i >= 0 {
			path = path[:i]
		}
		if i := strings.LastIndex(path, ":"); i > strings.LastIndex(path, "/") {
			path = path[:i]
		}
		return path == pattern
	}
}

// allowlistVariable es la variable de la raíz que crea la política de Binary Authorization
// (1-base, ADR 0029 §4) con los patrones de imágenes admitidas además de los repositorios.
const allowlistVariable = "binary_authorization_allowlist_patterns"

// allowlistValidation lee la expresión de la validación de binary_authorization_allowlist_patterns
// de las raíces de stages/ que declaran la variable, para no copiarla aquí. No fija la carpeta:
// busca en todos los variables.tf de stages/ (sin .terraform), y si varias raíces la declaran
// exige que la validación sea la misma en todas.
func allowlistValidation(t *testing.T, root string) *regexp.Regexp {
	t.Helper()
	validation := regexp.MustCompile(`can\(regex\("((?:[^"\\]|\\.)*)", p\)\)`)
	found := map[string]string{} // archivo → expresión
	err := filepath.WalkDir(filepath.Join(root, "stages"), func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && d.Name() == ".terraform" {
			return filepath.SkipDir
		}
		if d.IsDir() || d.Name() != "variables.tf" {
			return nil
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		src := string(b)
		start := strings.Index(src, `variable "`+allowlistVariable+`"`)
		if start < 0 {
			return nil
		}
		m := validation.FindStringSubmatch(src[start:])
		if m == nil {
			t.Errorf("%s declara %s sin la validación esperada", path, allowlistVariable)
			return nil
		}
		found[path] = m[1]
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(found) == 0 {
		t.Fatalf("ninguna raíz de stages/ declara %s", allowlistVariable)
	}
	var expr string
	for path, e := range found {
		if expr == "" {
			expr = e
		} else if e != expr {
			t.Errorf("%s valida %s con otra expresión: %q frente a %q", path, allowlistVariable, e, expr)
		}
	}
	return regexp.MustCompile(strings.ReplaceAll(expr, `\\`, `\`))
}

// TestConfigExampleBinaryAuthorization comprueba sin GCP que la imagen de Cloud Run de
// config.example.json pasa la política de Binary Authorization que crea 1-base (ALWAYS_DENY
// salvo los repositorios del proyecto y binary_authorization_allowlist_patterns, ADR 0029 §4), y
// que el patrón pasa la validación de la variable. Sin el patrón, 3-workloads fallaría en el
// apply.
func TestConfigExampleBinaryAuthorization(t *testing.T) {
	root := helpers.RepoRoot(t)
	cfg := loadConfig(t, filepath.Join(root, "tests", "e2e", "config.example.json"))

	image, _ := cfg.Stages[workloadsKey("dev")]["cloud_run_image"].(string)
	if image == "" {
		t.Fatalf("config.example.json: falta cloud_run_image en %s", workloadsKey("dev"))
	}
	raw, _ := cfg.Stages[keyBase][allowlistVariable].([]any)
	valid := allowlistValidation(t, root)
	covered := false
	for _, p := range raw {
		s, _ := p.(string)
		if !valid.MatchString(s) {
			t.Errorf("el patrón %q no pasa la validación de %s", s, allowlistVariable)
		}
		if binauthzPatternMatches(s, image) {
			covered = true
		}
	}
	if !covered {
		t.Errorf("cloud_run_image %q no está en %s de %s (%v): la política de 1-base la rechazaría", image, allowlistVariable, keyBase, raw)
	}
	if !binauthzPatternMatches("us-docker.pkg.dev/cloudrun/container/hello*", helpers.DefaultCloudRunImage) {
		t.Errorf("helpers.DefaultCloudRunImage %q ya no coincide con el patrón documentado", helpers.DefaultCloudRunImage)
	}
}

// TestConfigExampleVPNDR deja explícita la decisión sobre la VPN de DR del hub en la prueba de
// extremo a extremo (tests/README.md): enable_vpn_dr = true, como en el diseño, con 8 túneles.
func TestConfigExampleVPNDR(t *testing.T) {
	root := helpers.RepoRoot(t)
	cfg := loadConfig(t, filepath.Join(root, "tests", "e2e", "config.example.json"))
	v, ok := cfg.Stages[keyHub]["enable_vpn_dr"].(bool)
	if !ok || !v {
		t.Errorf("config.example.json: %s debe fijar enable_vpn_dr = true de forma explícita (decisión en tests/README.md); llegó %v", keyHub, cfg.Stages[keyHub]["enable_vpn_dr"])
	}
}

// TestConfigExampleRoots comprueba que config.example.json solo trae variables para raíces del
// ADR 0029 §2 (las que recorre la prueba, con dev) y que el proyecto único llega en common.
func TestConfigExampleRoots(t *testing.T) {
	root := helpers.RepoRoot(t)
	cfg := loadConfig(t, filepath.Join(root, "tests", "e2e", "config.example.json"))
	known := map[string]bool{keyBootstrap: true}
	for _, s := range stagesInOrder([]string{"dev"}) {
		known[s.Key] = true
	}
	for key := range cfg.Stages {
		if !known[key] {
			t.Errorf("config.example.json: raíz %q que no es del ADR 0029 §2", key)
		}
	}
	for key := range known {
		if _, ok := cfg.Stages[key]; !ok {
			t.Errorf("config.example.json: faltan las variables de %s", key)
		}
	}
	if id, _ := cfg.Common["project_id"].(string); id == "" {
		t.Error("config.example.json: common debe traer project_id (el proyecto único)")
	}
}

// TestStagesInOrder fija el orden y las cuentas de las raíces 1 → 3 (ADR 0029 §2 y la tabla de
// interfaces: llaves de stage_service_accounts).
func TestStagesInOrder(t *testing.T) {
	got := stagesInOrder([]string{"dev", "qa"})
	want := []stage{
		{Key: "1-base", Account: "1-base"},
		{Key: "2-networks", Account: "2-networks"},
		{Key: "2-networks/envs/dev", Account: "2-networks/dev", Env: "dev"},
		{Key: "3-workloads/envs/dev", Account: "3-workloads/dev", Env: "dev"},
		{Key: "2-networks/envs/qa", Account: "2-networks/qa", Env: "qa"},
		{Key: "3-workloads/envs/qa", Account: "3-workloads/qa", Env: "qa"},
	}
	if len(got) != len(want) {
		t.Fatalf("stagesInOrder: %d raíces, se esperaban %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("stagesInOrder[%d] = %+v, se esperaba %+v", i, got[i], want[i])
		}
	}
}

// TestProjectFromSelfLink prueba sin GCP cómo se saca el proyecto de un network_self_link.
func TestProjectFromSelfLink(t *testing.T) {
	cases := []struct {
		link, want string
		ok         bool
	}{
		{"https://www.googleapis.com/compute/v1/projects/example-project/global/networks/bnt-dev-vpc", "example-project", true},
		{"projects/example-project/global/networks/bnt-dev-vpc", "example-project", true},
		{"//compute.googleapis.com/projects/p-1/global/networks/n", "p-1", true},
		{"global/networks/bnt-dev-vpc", "", false},
		{"projects/", "", false},
		{"", "", false},
	}
	for _, c := range cases {
		got, err := projectFromSelfLink(c.link)
		if (err == nil) != c.ok || got != c.want {
			t.Errorf("projectFromSelfLink(%q) = %q, %v; se esperaba %q (ok %v)", c.link, got, err, c.want, c.ok)
		}
	}
}

func TestBinauthzPatternMatches(t *testing.T) {
	cases := []struct {
		pattern, image string
		want           bool
	}{
		{"us-docker.pkg.dev/cloudrun/container/hello*", "us-docker.pkg.dev/cloudrun/container/hello:latest", true},
		{"us-docker.pkg.dev/cloudrun/container/hello*", "us-docker.pkg.dev/cloudrun/container/hello/otra", false},
		{"us-docker.pkg.dev/p/r/**", "us-docker.pkg.dev/p/r/app/img:1", true},
		{"us-docker.pkg.dev/p/r/**", "us-docker.pkg.dev/p/r2/img:1", false},
		{"us-docker.pkg.dev/p/r/img", "us-docker.pkg.dev/p/r/img:1", true},
		{"us-docker.pkg.dev/p/r/img", "us-docker.pkg.dev/p/r/img@sha256:abc", true},
		{"us-docker.pkg.dev/p/r/img", "us-docker.pkg.dev/p/r/img2:1", false},
	}
	for _, c := range cases {
		if got := binauthzPatternMatches(c.pattern, c.image); got != c.want {
			t.Errorf("%s ~ %s: %v, se esperaba %v", c.pattern, c.image, got, c.want)
		}
	}
}
