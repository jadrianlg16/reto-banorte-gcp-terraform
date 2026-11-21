package helpers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/shell"
)

// Gcloud corre gcloud con args y devuelve su salida estándar. En Windows exec encuentra
// gcloud.cmd por PATHEXT; no se invoca ningún shell, así que el mismo código corre en
// Windows, macOS y Linux.
func GcloudE(t testing.TB, ctx context.Context, args ...string) (string, error) {
	t.Helper()
	cmd := &shell.Command{
		Command: "gcloud",
		Args:    append(append([]string{}, args...), "--quiet"),
		Logger:  logger.Discard,
	}
	return shell.RunCommandContextAndGetStdOutE(t, ctx, cmd)
}

// GcloudJSONE corre gcloud con --format=json y decodifica la salida en out.
func GcloudJSONE(t testing.TB, ctx context.Context, out any, args ...string) error {
	t.Helper()
	stdout, err := GcloudE(t, ctx, append(append([]string{}, args...), "--format=json")...)
	if err != nil {
		return fmt.Errorf("gcloud %s: %w", strings.Join(args, " "), err)
	}
	if err := json.Unmarshal([]byte(stdout), out); err != nil {
		return fmt.Errorf("gcloud %s: salida no es JSON: %w", strings.Join(args, " "), err)
	}
	return nil
}

// GcloudJSON es GcloudJSONE que falla la prueba ante un error y devuelve el objeto.
func GcloudJSON(t testing.TB, ctx context.Context, args ...string) map[string]any {
	t.Helper()
	var out map[string]any
	if err := GcloudJSONE(t, ctx, &out, args...); err != nil {
		t.Fatal(err)
	}
	return out
}

// GcloudJSONList es GcloudJSON para comandos que devuelven una lista.
func GcloudJSONList(t testing.TB, ctx context.Context, args ...string) []any {
	t.Helper()
	var out []any
	if err := GcloudJSONE(t, ctx, &out, args...); err != nil {
		t.Fatal(err)
	}
	return out
}

// GcloudObjectE devuelve el objeto JSON de gcloud o el error, sin fallar la prueba (para usar
// dentro de WaitFor, donde un t.Fatal cortaría los reintentos).
func GcloudObjectE(t testing.TB, ctx context.Context, args ...string) (map[string]any, error) {
	t.Helper()
	var out map[string]any
	err := GcloudJSONE(t, ctx, &out, args...)
	return out, err
}

// GcloudListE es GcloudObjectE para comandos que devuelven una lista.
func GcloudListE(t testing.TB, ctx context.Context, args ...string) ([]any, error) {
	t.Helper()
	var out []any
	err := GcloudJSONE(t, ctx, &out, args...)
	return out, err
}

// WaitFor reintenta check hasta que devuelva nil o se agote timeout (cada interval).
func WaitFor(t testing.TB, ctx context.Context, what string, timeout, interval time.Duration, check func() error) {
	t.Helper()
	retries := int(timeout / interval)
	if retries < 1 {
		retries = 1
	}
	retry.DoWithRetryContext(t, ctx, what, retries, interval, func() (string, error) {
		if err := check(); err != nil {
			return "", err
		}
		return "ok", nil
	})
}

// Path recorre obj (resultado de json.Unmarshal) por una ruta separada por puntos. Los
// segmentos numéricos indexan listas: "networkInterfaces.0.accessConfigs".
func Path(obj any, path string) (any, bool) {
	cur := obj
	for _, seg := range strings.Split(path, ".") {
		switch node := cur.(type) {
		case map[string]any:
			v, ok := node[seg]
			if !ok {
				return nil, false
			}
			cur = v
		case []any:
			i, err := strconv.Atoi(seg)
			if err != nil || i < 0 || i >= len(node) {
				return nil, false
			}
			cur = node[i]
		default:
			return nil, false
		}
	}
	return cur, true
}

// PathString devuelve el valor de la ruta como texto ("" si no existe).
func PathString(obj any, path string) string {
	v, ok := Path(obj, path)
	if !ok || v == nil {
		return ""
	}
	switch x := v.(type) {
	case string:
		return x
	case float64:
		return strconv.FormatFloat(x, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(x)
	default:
		b, _ := json.Marshal(x)
		return string(b)
	}
}

// PathBool devuelve el valor booleano de la ruta (false si no existe).
func PathBool(obj any, path string) bool {
	v, ok := Path(obj, path)
	if !ok {
		return false
	}
	b, _ := v.(bool)
	return b
}

// PathList devuelve la lista de la ruta (nil si no existe o no es lista).
func PathList(obj any, path string) []any {
	v, ok := Path(obj, path)
	if !ok {
		return nil
	}
	l, _ := v.([]any)
	return l
}

// ParseSeconds convierte una duración de la API ("7776000s") a segundos.
func ParseSeconds(s string) (int64, error) {
	return strconv.ParseInt(strings.TrimSuffix(strings.TrimSpace(s), "s"), 10, 64)
}

// LastSegment devuelve lo que sigue a la última barra ("projects/p/x/y" → "y").
func LastSegment(s string) string {
	if i := strings.LastIndex(s, "/"); i >= 0 {
		return s[i+1:]
	}
	return s
}
