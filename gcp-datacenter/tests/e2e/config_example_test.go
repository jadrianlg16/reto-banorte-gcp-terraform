package e2e

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/ext/typeexpr"
	"github.com/hashicorp/hcl/v2/hclparse"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/convert"
	ctyjson "github.com/zclconf/go-cty/cty/json"

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

// rootVariable es una variable que declara una raíz de stages/.
type rootVariable struct {
	Type     cty.Type // cty.DynamicPseudoType si no declara type
	Required bool     // sin default: Terraform la exige
}

// rootVariables lee los bloques variable de los *.tf de una raíz (sin subcarpetas) con el
// analizador de HCL y el de restricciones de tipo de Terraform (con optional()).
func rootVariables(t *testing.T, dir string) map[string]rootVariable {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(dir, "*.tf"))
	if err != nil || len(files) == 0 {
		t.Fatalf("%s: sin archivos .tf (%v)", dir, err)
	}
	parser := hclparse.NewParser()
	vars := map[string]rootVariable{}
	for _, f := range files {
		file, diags := parser.ParseHCLFile(f)
		if diags.HasErrors() {
			t.Fatalf("%s: %s", f, diags.Error())
		}
		body, ok := file.Body.(*hclsyntax.Body)
		if !ok {
			t.Fatalf("%s: no es sintaxis nativa de HCL", f)
		}
		for _, b := range body.Blocks {
			if b.Type != "variable" || len(b.Labels) != 1 {
				continue
			}
			v := rootVariable{Type: cty.DynamicPseudoType, Required: true}
			if a, ok := b.Body.Attributes["type"]; ok {
				ty, _, diags := typeexpr.TypeConstraintWithDefaults(a.Expr)
				if diags.HasErrors() {
					t.Fatalf("%s: variable %s: %s", f, b.Labels[0], diags.Error())
				}
				v.Type = ty
			}
			if _, ok := b.Body.Attributes["default"]; ok {
				v.Required = false
			}
			vars[b.Labels[0]] = v
		}
	}
	return vars
}

// jsonFitsType dice si un valor de JSON (como lo deja encoding/json) se puede asignar a una
// variable del tipo ty, con la misma conversión que hace Terraform con un -var-file JSON: el
// JSON da objetos y tuplas, que se convierten al tipo de la variable (un objeto no pasa a set o
// list, un arreglo no pasa a map u object, "abc" no pasa a number, falta un atributo que no es
// optional...). Devuelve el error de la conversión, con la ruta dentro del valor.
func jsonFitsType(value any, ty cty.Type) error {
	b, err := json.Marshal(value)
	if err != nil {
		return err
	}
	implied, err := ctyjson.ImpliedType(b)
	if err != nil {
		return err
	}
	v, err := ctyjson.Unmarshal(b, implied)
	if err != nil {
		return err
	}
	if _, err := convert.Convert(v, ty); err != nil {
		var pe cty.PathError
		if errors.As(err, &pe) && len(pe.Path) > 0 {
			return fmt.Errorf("%s: %w", pathString(pe.Path), err)
		}
		return err
	}
	return nil
}

func pathString(p cty.Path) string {
	var sb strings.Builder
	for _, step := range p {
		switch s := step.(type) {
		case cty.GetAttrStep:
			sb.WriteString("." + s.Name)
		case cty.IndexStep:
			if s.Key.Type() == cty.String {
				fmt.Fprintf(&sb, "[%q]", s.Key.AsString())
			} else if s.Key.Type() == cty.Number {
				fmt.Fprintf(&sb, "[%s]", s.Key.AsBigFloat().String())
			} else {
				sb.WriteString("[?]")
			}
		}
	}
	return strings.TrimPrefix(sb.String(), ".")
}

// TestConfigExampleRoots comprueba que config.example.json sirve para aplicar las raíces que
// recorre la prueba (ADR 0029 §2, con dev), contra los variables.tf del árbol:
//   - solo trae raíces del ADR 0029 §2, todas ellas, y el proyecto único en common;
//   - por raíz, con las mismas variables que arma la prueba (common, la raíz y lo que inyecta:
//     state_bucket, deletion_protection de las cargas de dev, labels), están todas las variables
//     sin default;
//   - cada valor cabe en el tipo de la variable (set/list con arreglos, map/object con objetos,
//     string, number, bool, y lo de adentro);
//   - la llave de la raíz no trae variables que la raíz no declara (las de common sí pueden
//     sobrar: se comparten).
//
// Si otra rama agrega una variable obligatoria a una raíz, esta prueba falla hasta agregarla al
// ejemplo.
func TestConfigExampleRoots(t *testing.T) {
	root := helpers.RepoRoot(t)
	cfg := loadConfig(t, filepath.Join(root, "tests", "e2e", "config.example.json"))
	stages := append([]stage{{Key: keyBootstrap}}, stagesInOrder([]string{"dev"})...)
	known := map[string]bool{}
	for _, s := range stages {
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

	run := &e2eRun{t: t, root: root, cfg: cfg, bucket: "bucket-de-la-prueba"}
	for _, s := range stages {
		declared := rootVariables(t, run.dir(s.Key))
		// Lo mismo que pasa la prueba a cada raíz (bootstrap y apply en stages_test.go).
		var injected map[string]any
		if s.Key != keyBootstrap {
			injected = run.injected(s)
		}
		vars := cfg.varsFor(s.Key, "e2e-ejemplo", injected)

		names := make([]string, 0, len(declared))
		for name := range declared {
			names = append(names, name)
		}
		sort.Strings(names)
		for _, name := range names {
			v := declared[name]
			value, ok := vars[name]
			if !ok || value == nil {
				if v.Required {
					t.Errorf("config.example.json: %s declara %s sin default y el ejemplo no la trae (ni en common ni en %q)", s.Key, name, s.Key)
				}
				continue
			}
			if err := jsonFitsType(value, v.Type); err != nil {
				t.Errorf("config.example.json: %s.%s no cabe en %s: %v", s.Key, name, typeexpr.TypeString(v.Type), err)
			}
		}
		for name := range cfg.Stages[s.Key] {
			if _, ok := declared[name]; !ok {
				t.Errorf("config.example.json: %q trae %s, que la raíz no declara", s.Key, name)
			}
		}
	}
}

// TestJSONFitsType prueba sin GCP la comparación de tipos de TestConfigExampleRoots, con el caso
// de la revisión (applications como objeto en una variable set(string)).
func TestJSONFitsType(t *testing.T) {
	cases := []struct {
		typ   string
		value string
		ok    bool
	}{
		{`set(string)`, `{"app": {"apis": [], "secrets": []}}`, false},
		{`set(string)`, `["app"]`, true},
		{`list(string)`, `"app"`, false},
		{`map(list(string))`, `{"admin@example.com": ["LEGAL", "SECURITY"]}`, true},
		{`map(list(string))`, `[["LEGAL"]]`, false},
		{`map(string)`, `{"a": {"b": "c"}}`, false},
		{`string`, `1000`, true}, // Terraform convierte number a string
		{`number`, `"1000"`, true},
		{`number`, `"mil"`, false},
		{`bool`, `true`, true},
		{`bool`, `"quizá"`, false},
		{`object({ a = string, b = optional(number, 1) })`, `{"a": "x"}`, true},
		{`object({ a = string, b = optional(number, 1) })`, `{"b": 2}`, false},
		{`list(object({ cidr_block = string }))`, `[{"cidr_block": "10.0.0.0/8"}]`, true},
		{`list(object({ cidr_block = string }))`, `{"cidr_block": "10.0.0.0/8"}`, false},
		{`any`, `{"x": [1, "y"]}`, true},
	}
	for _, c := range cases {
		expr, diags := hclsyntax.ParseExpression([]byte(c.typ), "tipo.tf", hcl.InitialPos)
		if diags.HasErrors() {
			t.Fatalf("%s: %s", c.typ, diags.Error())
		}
		ty, _, diags := typeexpr.TypeConstraintWithDefaults(expr)
		if diags.HasErrors() {
			t.Fatalf("%s: %s", c.typ, diags.Error())
		}
		var value any
		if err := json.Unmarshal([]byte(c.value), &value); err != nil {
			t.Fatalf("%s: %v", c.value, err)
		}
		if err := jsonFitsType(value, ty); (err == nil) != c.ok {
			t.Errorf("%s ← %s: error %v, se esperaba ok=%v", c.typ, c.value, err, c.ok)
		}
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
