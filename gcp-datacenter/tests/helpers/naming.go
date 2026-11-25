package helpers

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/gruntwork-io/terratest/modules/random"
)

// Run identifica una ejecución de una prueba. Todos los nombres que crea la prueba derivan de
// ID, así que dos pruebas en paralelo (o dos corridas seguidas en el mismo proyecto) no chocan.
type Run struct {
	// ID: seis caracteres en minúsculas y dígitos (random.UniqueID en minúsculas).
	ID string
	// Prefix: "t" + cinco caracteres del ID. Cumple la validación más estricta de prefix en
	// los módulos (^[a-z][a-z0-9]{1,5}$) y hace únicos los nombres <prefix>-<entorno>-…
	Prefix string
	// Module: nombre corto del módulo bajo prueba, para el ID del proyecto efímero.
	Module string
}

var nonAlnum = regexp.MustCompile(`[^a-z0-9]`)

// NewRun crea los identificadores de una ejecución para el módulo dado.
func NewRun(module string) Run {
	id := strings.ToLower(random.UniqueID())
	return Run{ID: id, Prefix: "t" + id[:5], Module: module}
}

// ProjectID arma el ID del proyecto efímero: "tt-<módulo>-<id>", a lo sumo 24 caracteres
// (el límite de GCP es 30) y con la forma ^[a-z][a-z0-9-]{4,28}[a-z0-9]$.
func (r Run) ProjectID() string {
	short := nonAlnum.ReplaceAllString(strings.ToLower(r.Module), "")
	if len(short) > 14 {
		short = short[:14]
	}
	return fmt.Sprintf("tt-%s-%s", short, r.ID)
}

// Name arma un nombre de recurso único "<prefix>-<parte>" para lo que crean los fixtures
// alrededor del módulo (redes, llaves, cuentas de servicio).
func (r Run) Name(part string) string {
	return fmt.Sprintf("%s-%s", r.Prefix, part)
}
