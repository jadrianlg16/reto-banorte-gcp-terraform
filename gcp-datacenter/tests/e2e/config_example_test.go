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

// allowlistValidation lee de la variable binary_authorization_allowlist_patterns de la etapa 4 la
// expresión de su validación, para no copiarla aquí.
func allowlistValidation(t *testing.T, root string) *regexp.Regexp {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, "stages", "4-projects", "envs", "dev", "variables.tf"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(b)
	start := strings.Index(src, `variable "binary_authorization_allowlist_patterns"`)
	if start < 0 {
		t.Fatal("4-projects/envs/dev no declara binary_authorization_allowlist_patterns")
	}
	m := regexp.MustCompile(`can\(regex\("((?:[^"\\]|\\.)*)", p\)\)`).FindStringSubmatch(src[start:])
	if m == nil {
		t.Fatal("no se encontró la validación de binary_authorization_allowlist_patterns")
	}
	return regexp.MustCompile(strings.ReplaceAll(m[1], `\\`, `\`))
}

// TestConfigExampleBinaryAuthorization comprueba sin GCP que la imagen de Cloud Run de
// config.example.json pasa la política de Binary Authorization que crea la etapa 4 (ALWAYS_DENY
// salvo el repositorio de la aplicación y binary_authorization_allowlist_patterns), y que el
// patrón pasa la validación de la variable. Sin el patrón, 5-workloads fallaría en el apply.
func TestConfigExampleBinaryAuthorization(t *testing.T) {
	root := helpers.RepoRoot(t)
	cfg := loadConfig(t, filepath.Join(root, "tests", "e2e", "config.example.json"))

	image, _ := cfg.Stages["5-workloads/envs/dev"]["cloud_run_image"].(string)
	if image == "" {
		t.Fatal("config.example.json: falta cloud_run_image en 5-workloads/envs/dev")
	}
	raw, _ := cfg.Stages["4-projects/envs/dev"]["binary_authorization_allowlist_patterns"].([]any)
	valid := allowlistValidation(t, root)
	covered := false
	for _, p := range raw {
		s, _ := p.(string)
		if !valid.MatchString(s) {
			t.Errorf("el patrón %q no pasa la validación de la etapa 4", s)
		}
		if binauthzPatternMatches(s, image) {
			covered = true
		}
	}
	if !covered {
		t.Errorf("cloud_run_image %q no está en binary_authorization_allowlist_patterns de 4-projects/envs/dev (%v): la política de la etapa 4 la rechazaría", image, raw)
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
	v, ok := cfg.Stages["3-networks"]["enable_vpn_dr"].(bool)
	if !ok || !v {
		t.Errorf("config.example.json: 3-networks debe fijar enable_vpn_dr = true de forma explícita (decisión en tests/README.md); llegó %v", cfg.Stages["3-networks"]["enable_vpn_dr"])
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
