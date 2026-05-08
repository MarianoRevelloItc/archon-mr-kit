# MR Workflow Kit — Manual

> 5 workflows + 3 custom commands for the cradle-to-PR pipeline.
> Built on Claude Code + Archon.

---

# Part 1 · Quick Start

## Lo que tenés que copiar

```
your-repo/
├── .archon/
│   ├── config.yaml
│   ├── workflows/         ← 5 archivos mr-*.yaml
│   └── commands/          ← 3 archivos mr-*.md
└── .claude/
    └── skills/            ← 4 skills (tdd, grill-me, to-prd, to-issues)
```

Copiá esos dos directorios al root de tu repo. Agregá `.archon/mcp/` a tu `.gitignore` (NO ignores todo `.archon/` — los workflows y commands se commitean).

## Pre-requisitos

- `git`, `gh` (GitHub CLI autenticado), `archon` (CLI instalado)
- Claude Code o Archon Web UI

## ⭐ Quick Reference — los 4 modos de implementación

Cuando tenés un issue (o varios) y querés implementarlo/s, elegí UN modo según tu necesidad:

### Modo 1 — Manual: vos revisás y mergeás cada PR

```bash
archon workflow run mr-issue-to-pr --branch fix/issue-N "Fix issue #N"
```

Produce un draft PR. **Vos** revisás, decidís y mergeás. Control total. Ideal cuando es algo crítico o no confiás en el auto-merge.

### Modo 2 — AFK secuencial: 1 issue, kit auto-mergea si limpio

```bash
archon workflow run mr-issue-to-pr-ralph --branch fix/issue-N "Fix issue #N"
```

Igual que el Modo 1, pero al final intenta auto-merge. **Mergea si**: validate verde + 0 CRITICAL pendientes + rebase OK. **Defiere a humano** si no cumple → label `needs-human-review`.

### Modo 3 — AFK secuencial varios issues (uno tras otro, MÁS SEGURO)

```bash
for n in 2 4 5 7; do
  archon workflow run mr-issue-to-pr-ralph --branch "fix/issue-$n" "Fix issue #$n"
done
```

Cada hijo arranca contra `main` ya con los anteriores mergeados → cero conflicts. Tiempo: `N × 45 min`.

### Modo 4 — AFK paralelo varios issues (RÁPIDO, riesgo de conflicts)

```bash
for n in 2 4 5 7; do
  nohup env -u CLAUDECODE archon workflow run mr-issue-to-pr-ralph \
    --branch "fix/issue-$n" "Fix issue #$n" \
    > "/tmp/mr-batch-logs/issue-$n.log" 2>&1 &
  disown $!
  sleep 5
done
```

Todos a la vez. Tiempo: `~max 45 min`. Riesgo: si dos issues tocan archivos comunes, los rebases pueden fallar y quedar como `needs-human-review`.

### Modo 5 (compuesto) — Plan + ejecutar con waves automáticas

```bash
# Paso 1: planificar (read-only, ~10-20 min)
archon workflow run mr-plan-waves --branch plan/sprint "Plan #2 #4 #5 #7 #8 #10 #11 #12"

# El workflow genera 2 scripts en /tmp/mr-plan-{timestamp}/:
#   - run-sequential.sh   (todo secuencial, más seguro)
#   - run-parallel.sh     (sigue el plan: paralelo donde safe, sequential donde overlap)

# Paso 2: ejecutar UNO de los dos (lee la salida del paso 1 para el path exacto)
nohup bash /tmp/mr-plan-2026-05-02-15-30/run-parallel.sh \
  > /tmp/wave-batch.log 2>&1 &
disown $!
```

Útil cuando son 5+ issues y no querés decidir a ojo qué va con qué.

### Tabla resumen — cuál usar cuándo

| Modo | Cuándo | Tiempo | Riesgo | AFK |
|---|---|---|---|---|
| 1 (manual) | 1 issue crítico | ~45min activo | Mínimo | No |
| 2 (ralph 1 issue) | 1 issue rutinario | ~45min AFK | Bajo | Sí |
| 3 (ralph secuencial N) | N issues que pueden tocar archivos comunes | N × 45min | Cero conflicts | Sí ✓ |
| 4 (ralph paralelo N) | N issues conocidos como independientes | ~45min total | Medio (conflicts) | Sí (con riesgo) |
| 5 (plan + waves) | 5+ issues, no sabés overlap | ~10min plan + ejecución | Bajo (plan optimiza) | Sí ✓ |

**Para máxima seguridad AFK: Modo 3 o Modo 5 con `run-sequential.sh`.**

---

## Bootstrap de un repo nuevo (una sola vez, ANTES de los 3 comandos)

```bash
archon workflow run mr-bootstrap-project --branch chore/bootstrap "Bootstrap"
```

Prepara el repo para que los demás workflows funcionen. Hace 6 cosas:

| Paso | Qué hace | Para qué |
|---|---|---|
| 1. **Precheck** | Verifica que `git`, `gh` y `archon` estén instalados, que `gh auth status` esté logueado, y que estés en un git repo | Falla rápido si falta una dependencia |
| 2. **Scaffold `.archon/`** | Crea `.archon/workflows/`, `.archon/commands/`, `.archon/config.yaml` (si no existen) | Estructura mínima que Archon necesita para descubrir el kit |
| 3. **Refina `.gitignore`** | Si tenías `.archon/` ignorado entero, lo cambia a solo `.archon/mcp/` | Los workflows y commands se commitean (son la fuente de verdad), solo `mcp/` queda fuera porque puede tener secretos |
| 4. **Renderiza `CLAUDE.md`** | Detecta el stack (Node/Python/Rust/Go) y escribe un template con comandos, layout, convenciones | Los workflows leen `CLAUDE.md` al implementar (lo necesita `mr-tdd-implement`) |
| 5. **Crea labels en GitHub** | `prd`, `auto-followup`, `HITL`, `AFK` (vía `gh label create`) | `mr-idea-to-prd` etiqueta el PRD parent; `mr-prd-to-issues` etiqueta children como AFK/HITL; `mr-promote-followups` etiqueta los issues nuevos como `auto-followup`. Sin estas labels los workflows fallan |
| 6. **Crea PR template** | `.github/pull_request_template.md` con secciones AC Coverage + Validation gates | Cuando `mr-issue-to-pr` ejecuta `gh pr create`, llena este template automáticamente con los datos del run |

**Idempotente**: si lo corrés y algo ya existe (CLAUDE.md, una label, etc.), lo skipea. Podés re-correrlo sin riesgo.

**Cuándo NO correrlo**: si tu repo ya tiene `.archon/` con workflows del kit, las labels en GitHub, y un CLAUDE.md — ya estás bootstrappeado.

## El flujo completo en 3 comandos

### Paso 1 — Tu idea fuzzy se convierte en un PRD claro

Te hace preguntas (3 rondas: foundation, deep dive, scope), explora el codebase, y produce un PRD posteado como GitHub issue con label `prd`. *Interactivo, ~30-60 min.*

```bash
archon workflow run mr-idea-to-prd --branch prd/{slug} "{tu idea}"
```

### Paso 2 — El PRD se parte en issues implementables

Lee el PRD, propone N "tracer-bullet" slices (cada uno cruza schema → API → UI → tests), te quiziea hasta que aprobás, y crea los N child issues con label `AFK` o `HITL`. *Semi-interactivo, ~10-15 min.*

```bash
archon workflow run mr-prd-to-issues --branch split/{slug} "Split PRD #{N}"
```

### Paso 3a — Un issue se convierte en un PR mergeable

Investiga el issue, implementa con TDD estricto (red→green por behavior), valida en multi-capas (CODE/HTTP/DOM/STACK), abre PR draft, lo revisa con 5 agentes en paralelo, auto-fixea CRITICAL/HIGH, y promueve MEDIUM/LOW como follow-up issues. *Autónomo, ~15-90 min.*

```bash
archon workflow run mr-issue-to-pr --branch fix/issue-{N} "Fix issue #{N}"
```

### Paso 3b (opcional) — Batch: lanzar N `mr-issue-to-pr` en paralelo

No hay workflow batch dedicado (se intentó `mr-batch-issue-to-pr` y se descartó — ver sección 3.5). Para correr N issues en paralelo, usá el siguiente patrón **bash con `nohup ... &`** que spawnea cada workflow detached del shell padre. Es robusto: cada uno corre como proceso top-level independiente, sobreviven aunque cierres la terminal, no hay zombies.

```bash
cd "ruta/a/tu/repo"
mkdir -p /tmp/mr-batch-logs

for n in 2 4 7 10 11; do  # ← acá tu lista de issues
  nohup env -u CLAUDECODE archon workflow run mr-issue-to-pr \
    --branch "fix/issue-$n" "Fix issue #$n" \
    > "/tmp/mr-batch-logs/issue-$n.log" 2>&1 &
  PID=$!
  disown $PID 2>/dev/null
  echo "  ✓ Issue #$n  → PID $PID"
  sleep 5  # stagger 5s entre lanzamientos para no saturar archon CLI startup
done
```

**Cap de concurrencia**: lo controla `MAX_CONCURRENT_CONVERSATIONS` en `~/.archon/.env` (default 10). Si lanzás más de ese cap, los excedentes se encolan vía Archon.

**Para monitorear**:

```bash
# Procesos vivos
ps aux | grep "archon workflow run mr-issue-to-pr" | grep -v grep

# Status en DB Archon
sqlite3 -column -header ~/.archon/archon.db \
  "SELECT user_message, status, last_activity_at FROM remote_agent_workflow_runs \
   WHERE user_message LIKE 'Fix issue #%' AND started_at >= datetime('now', '-3 hours') \
   ORDER BY started_at DESC"

# PRs creados (van apareciendo a medida que cada hijo termina)
gh pr list --state open --search "head:fix/issue-"
```

**Tiempo esperado**: ~30-45 min por issue. Con cap 5 y 6 issues = ~60-90 min wall-clock total.

## Uso desde la web UI de Archon

1. Hacé commit y push de `.archon/` y `.claude/skills/` a tu repo
2. Abrí Archon web UI
3. Los workflows `mr-*` aparecen en el listado automáticamente
4. Para correrlos: clickeás el nombre, ponés el mensaje, elegís el branch

## Validar que todo está bien instalado

```bash
# Lista limpia de los 5 workflows del kit (ignora menciones en descripciones de otros)
archon workflow list 2>&1 | grep -E '^\s+mr-' | sort

# Valida estructura de los 5 workflows
archon validate workflows 2>&1 | grep -E '^\s+mr-'

# Valida los 3 commands custom
archon validate commands 2>&1 | grep -E '^\s+mr-'
```

Esperado:

```
mr-bootstrap-project
mr-idea-to-prd
mr-issue-to-pr
mr-prd-to-issues

  mr-bootstrap-project                     ok
  mr-idea-to-prd                           ok
  mr-issue-to-pr                           ok
  mr-prd-to-issues                         ok

  mr-multi-validate                        ok
  mr-promote-followups                     ok
  mr-tdd-implement                         ok
```

Si todo dice `ok`, el kit está sano.

---

---

# Part 2 · Reference exhaustiva

## 1. Qué hay en el kit

### Workflows (6)

| Workflow | Tipo | Input | Output | Tiempo |
|---|---|---|---|---|
| `mr-bootstrap-project` | autónomo | repo nuevo | `.archon/`, labels, PR template, CLAUDE.md | ~2 min |
| `mr-idea-to-prd` | interactivo | idea libre | PRD como GitHub issue (label `prd`) | ~30-60 min |
| `mr-prd-to-issues` | semi-interactivo | número de issue PRD | N child issues con label `AFK`/`HITL` | ~10-15 min |
| `mr-issue-to-pr` | autónomo | número de issue | PR draft (vos mergeás) | ~15-90 min |
| `mr-issue-to-pr-ralph` | autónomo AFK | número de issue | PR draft + auto-merge si limpio | ~15-90 min |
| `mr-plan-waves` | autónomo read-only | N issue numbers | 2 scripts bash (sequential / parallel) en /tmp | ~10-20 min |

### Commands custom (3)

Estos commands son invocados por nodos `command:` dentro de los workflows. No los corres directamente.

| Command | Invocado desde | Qué hace |
|---|---|---|
| `mr-tdd-implement` | `mr-issue-to-pr` step `implement` | Implementa el issue con TDD estricto (red→green por behavior) |
| `mr-multi-validate` | `mr-issue-to-pr` step `validate` | Corre gates paralelos: CODE / HTTP / DOM / STACK |
| `mr-promote-followups` | `mr-issue-to-pr` step `promote-followups` | Convierte MEDIUM/LOW review findings en issues nuevos con label `auto-followup` |

### Skills referenciadas (4)

Las skills se inyectan en el contexto del agente vía el field `skills:` en los nodos. Necesitan estar en `.claude/skills/`.

| Skill | Referenciada por | Qué aporta |
|---|---|---|
| `tdd` | `mr-issue-to-pr` (step `implement`) | Metodología red-green-refactor, vertical slices, anti-patterns |
| `to-prd` | `mr-idea-to-prd` (step `generate`) | Template del PRD: Problem / Solution / User Stories / Decisions / Out of Scope |
| `grill-me` | `mr-idea-to-prd` (step `initiate`) | Estilo de preguntas: una a la vez, recommendation propia, branchea decisiones |
| `to-issues` | `mr-prd-to-issues` (step `draft-slices`) | Tracer-bullet vertical slices, HITL/AFK flagging, dep graph |

---

## 2. Arquitectura

### Diagrama del pipeline completo

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌────────────────┐
│   Idea      │───▶│  mr-idea-to-prd  │───▶│ mr-prd-to-issues │───▶│ mr-issue-to-pr │───▶ PR
│  (fuzzy)    │    │   (interactivo)  │    │ (semi-interactivo)│    │   (autónomo)   │     ×N
└─────────────┘    └──────────────────┘    └──────────────────┘    └────────────────┘
                          │                        │                        │
                          ▼                        ▼                        ▼
                   GitHub issue              N GitHub issues             GitHub PR
                   label: prd                label: AFK / HITL          mergeable
```

### Por qué tres átomos en vez de un mega-workflow

1. **Reusabilidad**: si ya tenés un PRD escrito a mano, saltás directo a `mr-prd-to-issues`. Si tenés un issue específico, `mr-issue-to-pr` solo.
2. **Debug**: si algo falla en una fase, no rompe todo el pipeline.
3. **HITL granular**: la fase 1 pausa en 3 gates con preguntas; la 2 pausa en 1 gate; la 3 es full autónoma. Encadenar fuerza pausas largas en un solo workflow.
4. **Brownfield friendly**: para un repo existente con issues abiertos, solo necesitás `mr-issue-to-pr`.

### No hay workflow padre que orqueste las 3 fases

Las fases 1 y 2 son intrínsecamente interactivas — el input del usuario es parte del diseño. No se pueden anidar en un workflow padre que también pause sin perder la naturaleza interactiva. Y para batch sobre la fase 3 (varios `mr-issue-to-pr` en paralelo), se intentó hacer un wrapper YAML (`mr-batch-issue-to-pr`) y se descartó — ver sección 3.5 más abajo. La conclusión: usá el patrón bash `nohup ... &` para batch (ver Part 1 Step 3b).

### Reuso de Archon defaults vs custom

`mr-issue-to-pr` es un fork quirúrgico de `archon-fix-github-issue`. Reusa 8 commands de Archon y solo customiza 3:

```
mr-issue-to-pr DAG (11 nodos):

extract-issue-number   ← REUSO (haiku, output_format=number)
fetch-issue            ← REUSO (bash + gh)
classify               ← REUSO (haiku, output_format)
web-research           ← REUSO (paralelo)
investigate            ← REUSO (cuando bug)        ──┐ trigger_rule:
plan                   ← REUSO (cuando feature)    ──┤ one_success
bridge-artifacts       ← REUSO (bash)              ──┘
implement              ★ CUSTOM (mr-tdd-implement)
validate               ★ CUSTOM (mr-multi-validate)
create-pr              ← REUSO (prompt + gh pr create)
review-scope           ← REUSO
review-classify        ← REUSO (haiku, output_format)
[5 review agents]      ← REUSO (paralelos, conditional)
synthesize             ← REUSO
self-fix               ← REUSO (CRITICAL/HIGH only)
promote-followups      ★ CUSTOM (mr-promote-followups)  ← reemplaza simplify-changes
report                 ← REUSO (issue-completion-report)
```

El `simplify-changes` de Archon original lo droppeamos porque en pruebas causaba scope creep (metió Vitest infra en un PR de UI fix).

---

## 2.5 Convención de labels y linking

Los workflows del kit dependen de una convención compartida de labels en GitHub y de un patrón de markdown en los body de los issues. Si respetás la convención (la setea automáticamente `mr-bootstrap-project`), todo el pipeline encaja.

### Labels

| Label | Color | Lo setea | Lo lee | Significado |
|---|---|---|---|---|
| `prd` | azul `#0366D6` | `mr-idea-to-prd` (paso final) | `mr-prd-to-issues` (al buscar el PRD parent) | Marca un issue como Product Requirements Document parent |
| `AFK` | verde `#0E8A16` | `mr-prd-to-issues` (en cada child autónomo) | filtros manuales con `gh issue list --label AFK` | Issue implementable sin design call humano |
| `HITL` | naranja `#D93F0B` | `mr-prd-to-issues` (en cada child que necesita design call) | filtros manuales — skipear del batch script | Necesita Human-in-the-loop antes de implementar |
| `auto-followup` | amarillo `#FBCA04` | `mr-promote-followups` (en cada finding MEDIUM/LOW promovido) | filtros manuales con `gh issue list --label auto-followup` | Issue auto-creado desde una review de PR |

### Linking parent ↔ child

Cuando `mr-prd-to-issues` parte un PRD, escribe en el body de **cada child** un bloque así:

```markdown
## Parent

#42

## What to build

...
```

Donde `#42` es el número del PRD parent. Esto es el ÚNICO mecanismo de linking — no usamos GitHub's "linked issues" feature porque no se puede setear vía `gh` CLI fácilmente.

Si querés filtrar issues children de un PRD a mano para batch-correrlos, podés usar:

```bash
gh issue list --label AFK --state open --json number,body --jq '.[] | select(.body | contains("## Parent\n\n#42")) | .number'
```

Y después feedear esos números al script bash de batch (Step 3b en Part 1).

### Implicaciones prácticas

- Si creás issues a mano y querés agruparlos como hijos de un PRD, agregales el bloque `## Parent\n\n#{N}` en el body
- Si la label `AFK` no está, los scripts batch que filtran por `--label AFK` no los encuentran
- Para tu caso brownfield (issues sueltos sin label), simplemente listalos explícitamente en el for-loop del script bash

### Aplicar la convención a issues existentes

Si tenés issues abiertos sin labels (típico brownfield), podés etiquetarlos en bulk:

```bash
# Aplicar AFK a una lista
for n in 7 8 11 13; do gh issue edit $n --add-label AFK; done

# O todos los open de un milestone
gh issue list --milestone "v1" --state open --json number --jq '.[].number' | \
  xargs -I {} gh issue edit {} --add-label AFK
```

Una vez etiquetados, `"all afk"` los encuentra.

---

## 3. Workflows en detalle

### 3.1 `mr-bootstrap-project`

**Cuándo correrlo**: una sola vez por repo nuevo, ANTES de usar los demás workflows.

**Qué crea**:

| Artifact | Contenido |
|---|---|
| `.archon/config.yaml` | `assistant: claude`, `worktree.baseBranch: main` |
| `.archon/workflows/` y `commands/` | dirs vacíos (ahí copiarás el kit) |
| `CLAUDE.md` | template basado en stack detectado (Python/Node/Rust/Go) |
| `.gitignore` | agrega `.archon/mcp/` (y limpia overly-broad `.archon/` si existía) |
| GitHub labels | `prd`, `auto-followup`, `HITL`, `AFK` |
| `.github/pull_request_template.md` | template con AC Coverage + Validation tables |

**DAG**:

```
precheck (verifica gh, archon, git)
    ├─▶ scaffold-archon
    │       ├─▶ update-gitignore
    │       ├─▶ render-claude-md
    │       └─▶ pr-template
    └─▶ create-labels (gh label create)
                                    ▼
                                 verify
                                    ▼
                                 report
```

**Idempotente**: si algún paso ya está hecho, lo skipea.

**No lo uses si**: tu repo ya tiene `.archon/`. Eso ya está bootstrappeado.

---

### 3.2 `mr-idea-to-prd`

**Cuándo correrlo**: tenés una idea fuzzy y querés convertirla en un PRD bien estructurado posteado como issue parent en GitHub.

**Modelo mental**: 3 gates de preguntas, una respuesta libre del usuario por gate, después un PRD validado contra el codebase.

**DAG**:

```
initiate (sonnet + grill-me skill)
   ├─ Restate la idea
   └─ Pregunta 5 cosas: who/what/why/why-now/how-success
        │
        ▼
foundation-gate (capture user response)
        │
        ▼
research (sonnet)
   ├─ Web research (light)
   ├─ Codebase exploration (deep, file:line refs)
   └─ Pregunta 5 cosas: vision/primary-user/JTBD/non-users/constraints
        │
        ▼
deepdive-gate (capture user response)
        │
        ▼
technical (sonnet)
   ├─ Inventario de primitivas (DB / API / Service / UI / Test)
   ├─ Smallest viable change
   └─ Pregunta 5 cosas: MVP/must-haves/hypothesis/out-of-scope/open-questions
        │
        ▼
scope-gate (capture user response)
        │
        ▼
generate (sonnet + to-prd skill)
   └─ Escribe el PRD usando el template de to-prd
        │
        ▼
validate (sonnet)
   └─ Re-checa cada referencia file:line/endpoint/columna del PRD
        │
        ▼
post-to-github
   └─ gh issue create --label prd --body-file <PRD>
```

**Output**:
- Local: `$ARTIFACTS_DIR/prds/{slug}.prd.md`
- Remote: GitHub issue con label `prd`

**Adaptación del template Archon**: `archon-interactive-prd` usa un template de 12 secciones súper detalladas. Nosotros usamos el template más conciso de la skill `to-prd` (Problem / Solution / User Stories / Implementation Decisions / Testing / Out of Scope / Further Notes), que se traduce mejor a un GitHub issue.

**No lo uses si**: ya tenés un PRD escrito a mano (saltá a `mr-prd-to-issues`).

---

### 3.3 `mr-prd-to-issues`

**Cuándo correrlo**: tenés un PRD como GitHub issue (con label `prd`) y querés partirlo en N issues implementables.

**Modelo mental**: el agente propone vertical slices (tracer-bullet), vos los revisás, iteran hasta aprobar, después se crean los issues en orden de dependencias.

**DAG**:

```
extract-prd-issue (haiku) → fetch-prd (bash + gh)
                                    │
                                    ▼
                            draft-slices (sonnet + to-issues skill)
                              │
                              ▼
                       refine-slices (loop, interactive)
                              │   until: SLICES_APPROVED
                              │   max_iterations: 10
                              ▼
                          create-issues
                          ├─ Topo-sort por blockers
                          ├─ gh issue create --label AFK|HITL (uno a uno)
                          ├─ Substituye refs reales en "Blocked by"
                          └─ Comenta en parent PRD con la lista
```

**El loop `refine-slices`**: itera hasta que el usuario diga "approved" / "looks good" / "ship it". Si el usuario hace una pregunta o pide cambios, el loop sigue.

**Reglas de slicing** (heredadas de la skill `to-issues`):
- Cada slice es un tracer-bullet: corta de schema → API → UI → tests
- Cada slice es demoable solo
- Marcado HITL (necesita design call) o AFK (autónomo)
- Preferir muchos slices finos sobre pocos gruesos

**Output**: N issues hijos en GitHub, con bodies que linkean al parent PRD y con `Blocked by` con números reales.

---

### 3.4 `mr-issue-to-pr` (★ el de mayor impacto)

**Cuándo correrlo**: tenés un issue (chico, AFK) y querés un PR review-ready, mergeable.

**Modelo mental**: 11 nodos. Investiga → planifica → implementa con TDD → valida en multi-capas → crea PR draft → review con 5 agentes paralelos → auto-fix solo CRITICAL/HIGH → promueve MEDIUM/LOW como follow-ups.

**DAG completo**:

```
PHASE 1: FETCH & CLASSIFY
extract-issue-number (haiku) → fetch-issue (bash) → classify (haiku, output_format)
                                                            │
                                              ┌─────────────┴─────────────┐
                                              ▼                           ▼
PHASE 2-3:                              web-research               investigate (bug) | plan (feature)
                                              └─────────────┬─────────────┘
                                                            ▼
                                                    bridge-artifacts (one_success)
                                                            │
                                                            ▼
PHASE 4: TDD IMPLEMENT                          implement [opus, fresh, skill: tdd]
                                                            │
                                                            ▼
PHASE 5: MULTI-VALIDATE                                 validate
                                                            │
                                                            ▼
PHASE 6: PR                                             create-pr
                                                            │
                                                            ▼
PHASE 7: REVIEW SCOPE                              review-scope → review-classify (haiku)
                                                            │
                            ┌──────────────┬───────────────┼────────────────┬──────────────┐
                            ▼              ▼               ▼                ▼              ▼
PHASE 8: 5 AGENTS    code-review   error-handling   test-coverage   comment-quality   docs-impact
                            └──────────────┴───────────────┼────────────────┴──────────────┘
                                                            ▼ (one_success)
PHASE 9: SYNTHESIZE                                    synthesize
                                                            │
                                                            ▼
                                                self-fix (CRITICAL/HIGH only)
                                                            │
                                                            ▼
PHASE 10: PROMOTE                              promote-followups (MEDIUM/LOW → issues)
                                                            │
                                                            ▼
PHASE 11: REPORT                                          report (gh issue comment)
```

**Diferencias vs `archon-fix-github-issue` original**:
1. `implement` (Archon `archon-fix-issue`) → **`mr-tdd-implement`** (TDD estricto, skill tdd, opus)
2. `validate` (Archon `archon-validate`) → **`mr-multi-validate`** (gates paralelos)
3. `simplify` (Archon `archon-simplify-changes`) → **DROP** (causaba scope creep)
4. `report` ← entre `self-fix` y `report` insertamos **`promote-followups`** (MEDIUM/LOW → issues)

**Variables de runtime**:
- `extract-issue-number`: usa solo Bash, output bare number (no markdown)
- `classify`: haiku, structured output con `issue_type` enum
- `implement`: opus 4.6 1M context, `idle_timeout: 1200000` (20 min por behavior)
- `validate`: `idle_timeout: 600000` (10 min)
- `review-classify`: haiku decide cuáles de los 5 agentes correr (code-review SIEMPRE corre, los otros condicionales)
- `synthesize`: `trigger_rule: one_success` — si 4 de 5 agentes fallan, igual procede con lo que hay

**Cuándo NO usarlo**:
- Issues HITL (necesitás un design call primero)
- Issues con scope >2 días de trabajo (partilo con `mr-prd-to-issues`)
- PRs ya creados (eso es review territory: usá `archon-comprehensive-pr-review`)
- Si querés AFK total (auto-merge) → usá `mr-issue-to-pr-ralph` (sección 3.5)

---

### 3.5 `mr-issue-to-pr-ralph` (AFK con auto-merge)

**Cuándo correrlo**: querés AFK total. Es la versión "no me hagas revisar" de `mr-issue-to-pr`.

**Diferencias vs `mr-issue-to-pr`**:

| Nodo | mr-issue-to-pr | mr-issue-to-pr-ralph |
|---|---|---|
| extract → fetch → classify → research → investigate/plan → bridge → implement → validate | Idéntico | Idéntico |
| `rebase-against-main` antes de `create-pr` | ❌ No | ✅ SÍ — defensa para parallel/staggered runs |
| create-pr → review-scope → 5 agents → synthesize → self-fix → promote-followups → report | Idéntico | Idéntico |
| `auto-merge-or-defer` después de report | ❌ No | ✅ SÍ — auto-mergea si threshold OK, sino label `needs-human-review` |

**Política de auto-merge (BALANCED)**:

```
mergea si:    validate verde + 0 CRITICAL pendientes + rebase OK
defiere si:   hay CRITICAL pendientes, validate falló, o rebase con conflict
```

**El nodo `rebase-against-main`**:

```
1. git fetch origin main
2. Si no estoy detrás → skip rebase
3. Si estoy detrás → git rebase origin/main
   - OK → escribe REBASE_OK a $ARTIFACTS_DIR/.rebase-status
   - CONFLICT → git rebase --abort, escribe REBASE_CONFLICT
4. Continúa al create-pr (incluso si conflict, el PR se crea — auto-merge step decidirá)
```

**El nodo `auto-merge-or-defer`** (último del DAG):

```
1. Lee .rebase-status, validation.md, consolidated-review.md, fix-report.md
2. Calcula CRITICAL_PENDING = total - fixed
3. Si REBASE_OK + ALL_PASS + CRITICAL_PENDING == 0:
     gh pr ready N
     gh pr merge N --squash --delete-branch
     comment al PR: "🤖 Auto-merged"
     escribe AUTO_MERGED a .merge-status
   Si NO:
     gh pr edit N --add-label "needs-human-review"
     comment al PR: "🚦 Auto-merge skipped — reasons: ..."
     escribe DEFERRED_TO_HUMAN a .merge-status
```

**Casos de uso**:

```bash
# 1 issue solo
archon workflow run mr-issue-to-pr-ralph --branch fix/issue-N "Fix #N"

# Batch secuencial (más seguro)
for n in 2 4 5; do
  archon workflow run mr-issue-to-pr-ralph --branch "fix/issue-$n" "Fix #$n"
done

# Batch paralelo
for n in ...; do
  nohup env -u CLAUDECODE archon workflow run mr-issue-to-pr-ralph \
    --branch "fix/issue-$n" "Fix #$n" & disown $!
  sleep 5
done

# Planificado por waves (ver 3.6 abajo)
archon workflow run mr-plan-waves "Plan #2 #4 #5 #7 #8"
nohup bash /tmp/mr-plan-.../run-parallel.sh > /tmp/log 2>&1 & disown $!
```

**Cuándo NO usarlo**:
- Querés revisar manualmente cada PR antes de mergear → usá `mr-issue-to-pr`
- El issue es crítico/security/breaking → revisión humana obligatoria

---

### 3.6 `mr-plan-waves` (analiza N issues, genera scripts de batch)

**Cuándo correrlo**: tenés 5+ issues abiertos y no sabés qué orden minimiza conflicts.

**Es READ-ONLY**: NO toca código, NO crea PRs, NO lanza otros workflows.

**Inputs**: lista de issue numbers en el message (ej: `"Plan #2 #4 #5 #7 #8"`).

**Outputs**:
1. **En pantalla**: el plan analizado + ubicación de scripts + cómo ejecutar
2. **En disco** (`/tmp/mr-plan-{timestamp}/`):
   - `run-sequential.sh` — todos los issues uno tras otro (cero paralelismo)
   - `run-parallel.sh` — sigue las recomendaciones por wave (paralelo donde safe, secuencial donde overlap)

Ambos scripts:
- Son ejecutables (`chmod +x`)
- Lanzan `mr-issue-to-pr-ralph` por cada issue
- Tienen lógica de espera entre waves
- Reportan al final qué se mergeó y qué quedó como `needs-human-review`

**DAG**:

```
parse-input            (bash) — extrae números del message
   ↓
analyze-overlap        (command mr-analyze-issue-overlap)
   ↓
generate-scripts       (bash) — escribe los 2 .sh con permisos
   ↓
present-plan           (prompt) — formatea y muestra todo en pantalla
```

**Cómo `mr-analyze-issue-overlap` predice files** (3 técnicas combinadas):

1. **Explicit paths in body**: regex de paths backtick-quoted o con `/`
2. **Function/class names → grep**: identifiers mencionados → busca dónde están definidos
3. **Architectural keywords → known hubs**: keywords como "signal/scanner/orchestrator/router/component" se mapean a probable hub files (vía grep contra el repo)

Las 3 técnicas se aplican siempre. Si el repo no tiene archivos que matcheen los patrones arquitectónicos, simplemente no aporta — el análisis sigue siendo válido pero menos preciso.

**Algoritmo de waves**: greedy graph coloring. Issues sin overlap → wave 1. Issues que comparten files (transitivamente) → mismo wave secuencial.

**Casos de uso**:

```bash
# Caso típico: tenés 8 issues, no sabés cómo agruparlos
archon workflow run mr-plan-waves --branch plan/sprint "Plan #2 #4 #5 #7 #8 #10 #11 #12"

# El workflow muestra plan en pantalla + paths a los 2 scripts
# Vos elegís cuál correr:

# Modo seguro (todo secuencial)
nohup bash /tmp/mr-plan-2026-05-02-15-30/run-sequential.sh \
  > /tmp/wave-batch.log 2>&1 &
disown $!

# Modo siguiendo plan (paralelo donde safe, secuencial donde overlap)
nohup bash /tmp/mr-plan-2026-05-02-15-30/run-parallel.sh \
  > /tmp/wave-batch.log 2>&1 &
disown $!
```

**Cuándo NO usarlo**:
- Tenés 1-2 issues solamente → directo con ralph
- Conocés bien la independencia de los issues → directo con script bash
- Necesitás control granular del orden → manual

---

### 3.7 Patrón de batch directo (sin mr-plan-waves)

**Para correr N `mr-issue-to-pr` en paralelo**, usá el patrón documentado en Part 1 Step 3b. Resumen:

```bash
cd "ruta/a/tu/repo"
mkdir -p /tmp/mr-batch-logs
for n in 2 4 7 10 11; do
  nohup env -u CLAUDECODE archon workflow run mr-issue-to-pr \
    --branch "fix/issue-$n" "Fix issue #$n" \
    > "/tmp/mr-batch-logs/issue-$n.log" 2>&1 &
  disown $! 2>/dev/null
  sleep 5
done
```

**Por qué este patrón funciona**: cada `archon workflow run` corre como **proceso top-level independiente**. `nohup` + `&` + `disown` lo desconecta del shell padre. Sobreviven aunque cierres la terminal. El cap de paralelismo lo respeta Archon vía `MAX_CONCURRENT_CONVERSATIONS` en `~/.archon/.env`.

**Por qué NO hay un workflow YAML batch dedicado**: ver siguiente sección de lecciones aprendidas.

---

### 3.8 Lecciones aprendidas — el intento `mr-batch-issue-to-pr`

> **Esta sección documenta un workflow que se intentó construir y se dropeó.** Si en el futuro querés retomar la idea de un wrapper batch nativo en YAML, lee esto antes para no chocar contra las mismas paredes.

**Idea original**: wrapper YAML que orquesta múltiples `mr-issue-to-pr` en paralelo, con detección de tipos de input, filtro de blockers, polling, reporte agregado.

**Resultado**: 4 bugs progresivos en cascada, fix tras fix, hasta finalmente descubrir un bug arquitectural irrecuperable (zombies). Se dropeó el workflow.

#### Los 4 bugs encontrados (en orden)

##### Bug 1 — Archon shell-escapa los `$nodeId.output.field`

```yaml
INPUT_TYPE="$classify-input.output.input_type"
```

Resulta en `INPUT_TYPE="'list'"` — single quotes embebidas en el valor. El `case "$INPUT_TYPE" in single|list)` no matchea.

**Fix**: `INPUT_TYPE=$(echo "$classify-input.output.input_type" | tr -d "'\"")` — strip explícito de quotes (mismo patrón que `archon-fix-github-issue` defaults).

**Lección**: para CUALQUIER substitución de `$nodeId.output.X` en bash nodes, asume que viene shell-escaped y strippeá quotes.

##### Bug 2 — Heredocs `<<PYEOF` no funcionan dentro de YAML

```bash
python3 - <<PYEOF
  ... python code ...
  PYEOF      # ← indentado por la estructura del case statement
```

Heredocs sin guión (`<<EOF`, no `<<-EOF`) requieren el closer en columna 0. YAML's `|` block scalar mantiene indentación relativa, entonces el `PYEOF` queda indentado en el bash actual → `syntax error: unexpected end of file`.

**Fix**: reemplazar TODOS los `python3 - <<PYEOF` con `python3 -c '...'` (single-quoted bash string preserva el python literal).

**Lección**: jamás usar `<<EOF`/`<<PYEOF` heredocs dentro de bash nodes en YAML. Usar `python3 -c` con env vars para pasar valores.

##### Bug 3 — Backslash en f-string expression

Dentro del `python3 -c '...'`, escribir:

```python
print(f"  #{c[\"number\"]}: {c[\"title\"]}")
```

Python <3.12 da `SyntaxError: f-string expression part cannot include a backslash`.

**Fix**: pre-extraer valores del dict ANTES del f-string:

```python
n = c["number"]
t = c["title"]
print(f"  #{n}: {t}")
```

**Lección**: dentro de `python3 -c '...'`, las comillas dobles dentro de python son LITERALES (no necesitan escape). Pero si necesitás indexar un dict con string en una expresión f-string, pre-extraé el valor a una variable.

##### Bug 4 — `$ARTIFACTS_DIR` no es bash variable

```bash
export ARTIFACTS_DIR INPUT_TYPE PRD_NUM NUMBERS FORCE
```

Archon substituye `$ARTIFACTS_DIR` en el SOURCE del bash (literal path baked-in), pero NO setea una bash variable. El `export ARTIFACTS_DIR` exporta una variable vacía → python's `os.environ["ARTIFACTS_DIR"]` raise `KeyError`.

**Fix**: asignar explícitamente antes de exportar:

```bash
export ARTIFACTS_DIR="$ARTIFACTS_DIR"
export INPUT_TYPE PRD_NUM NUMBERS FORCE
```

**Lección**: las variables Archon (`$ARTIFACTS_DIR`, `$WORKFLOW_ID`, etc.) se substituyen en el source pero NO existen como env vars en el shell del bash node. Si querés pasarlas a un subprocess (python, otro script), asignalas explícitamente: `export VAR="$VAR"`.

#### El bug arquitectural — el que nos hizo dropear el workflow

Después de fixear los 4 bugs anteriores, el workflow corrió ENTERO sin errores: classify-input, resolve-issue-set, filter-unblocked, invoke-children, wait-and-report. Todos los nodes completados, status=completed.

**PERO**: los 5 child workflows quedaron como **zombies** — registrados en la DB de Archon como `running`, sin proceso vivo ejecutándolos. Al cabo de 70 minutos: 0 artifacts escritos en cada child, 0 PRs creados.

**La causa raíz**:

```python
# En invoke-children:
result = subprocess.run(
    ["archon", "workflow", "run", "mr-issue-to-pr", ...],
    capture_output=True, text=True, timeout=60
)
```

El `timeout=60` mata el subprocess `archon workflow run` después de 60s. Pero ese subprocess es el que mantiene vivo al proceso de Claude que hace el trabajo del child. Al matarlo:
- DB queda con `status='running'`
- Worktree queda creado
- El proceso Claude del child muere también
- **Nadie está procesando ese workflow** — zombie

Y el `wait-and-report` (un `prompt:` node) tampoco hizo polling real — el AI agent decidió "ya está" y terminó. El orquestador completó en 2.5 minutos, dejando 5 zombies atrás.

#### Por qué es difícil de arreglar correctamente

Para que un wrapper YAML batch funcione bien, necesitás:

1. **Detached spawn** que sobreviva al subprocess wrapper. `nohup ... &` desde dentro de un `subprocess.run` es complicado — el subprocess debe terminar EXITOSAMENTE inmediatamente sin matar al child detached.
2. **Polling honesto** (no en un AI prompt — el agente termina antes). Tendría que ser bash en un loop con `sleep` + `archon workflow status`.
3. **Captura confiable de run-ids**. El parsing por regex del output del CLI es frágil (vimos truncamiento a 8 chars cuando el regex era ambiguo).
4. **Mecanismo de timeout / cancelación** consistente para zombies.

Cada uno de esos 4 puntos es resolvable individualmente, pero sumarlos en un YAML mantenible es alta complejidad.

#### Por qué el script bash funciona (lo que SÍ probamos y anduvo)

El patrón `nohup env -u CLAUDECODE archon workflow run ... > log 2>&1 &` con `disown` resuelve los 4 problemas de arriba simultáneamente:

- **Detached por design**: `nohup` + `&` + `disown` = proceso huérfano que sobrevive al shell padre
- **No requiere polling**: el usuario monitorea con comandos directos cuando quiere
- **Run-ids no se necesitan**: cada workflow se identifica por su branch, no por id
- **Sin orquestador**: no hay nada que pueda fallar arriba que mate los hijos

**El batch corrió 5 issues en paralelo (2, 4, 7, 10, 11) + 1 secuencial (12) en ~100 min total wall-clock, con 6 PRs draft creados, 21 auto-followups generados, 0 zombies, 0 recovery manual.**

#### Si en el futuro querés intentar un workflow YAML batch

Recomendaciones basadas en esta experiencia:

1. **Aceptá que es difícil** — no es 1-2 días de trabajo, es probable que sean ≥1 semana de iteración con muchos casos de borde
2. **Empezá por el polling honesto**: un nodo `bash:` con loop `while true; do ... done` (NO un `prompt:` node — los AI agents terminan antes)
3. **Spawneá detached desde día 1**: `nohup ... &` directamente en bash, NO `subprocess.run` desde python
4. **No parsees run-ids del stdout** — usá la DB de Archon directamente: `sqlite3 ~/.archon/archon.db "SELECT id FROM remote_agent_workflow_runs WHERE working_path LIKE '%fix/issue-N%' ORDER BY started_at DESC LIMIT 1"`
5. **Agregá un nodo `cleanup-zombies`** al inicio que cancele runs viejos en `running` sin proceso vivo
6. **Probá con 1 child primero** (`single` input type), después 2, después N. No saltees al test de 6 directamente
7. **Mirá `archon-test-loop-dag` y `archon-piv-loop`** — sus `loop:` nodes son el patrón nativo de Archon para iteración. Tal vez se pueda usar para polling
8. **Considera si vale la pena**: el script bash ya cubre el use case. Un workflow YAML solo tiene sentido si ofrece algo CUALITATIVAMENTE diferente (ej: integración con la web UI de Archon para visualizar el batch, reporte agregado en GitHub issue, telemetría)

#### Artifacts del intento (preservados en git history)

Los 5 commits del intento están en `main`:

```
afa29b4 fix(mr-batch-issue-to-pr): explicitly export ARTIFACTS_DIR for python subprocess
724cd41 fix(mr-batch-issue-to-pr): pre-extract dict values to avoid backslash in f-string
8440a6f fix(mr-batch-issue-to-pr): strip Archon-injected quotes + replace heredocs with python -c
d378697 chore: install mr-* workflow kit (Archon)   ← versión inicial con mr-batch-issue-to-pr.yaml
```

Para recuperar el YAML: `git show d378697:.archon/workflows/mr-batch-issue-to-pr.yaml` (o el último commit donde existió antes de borrar).

---

## 4. Custom commands en detalle

### 4.1 `mr-tdd-implement`

**Invocado desde**: `mr-issue-to-pr` step `implement`.

**Lee**: `$ARTIFACTS_DIR/investigation.md` (bugs) o `$ARTIFACTS_DIR/plan.md` (features).
**Escribe**: `$ARTIFACTS_DIR/implementation.md` + commits en el branch.

**Fases**:

| # | Fase | Qué hace |
|---|---|---|
| 0 | ORIENT | Detecta backend/frontend scope, lee CLAUDE.md, parsea ACs del artifact |
| 1 | DEPENDENCIES | Instala Python deps (si backend/) y/o npm ci (si frontend/) |
| 2 | PLAN BEHAVIORS | Decompone cada AC en behaviors observables, escribe scratchpad `.tdd-behaviors.md` |
| 3 | TDD LOOP | Por cada behavior: RED → GREEN → type-check + lint → mark DONE |
| 4 | SCOPE GUARD | Audita el diff: cada línea cambiada debe trazar a un AC o test |
| 5 | WRITE | Genera `implementation.md` con tabla de coverage |
| 6 | REPORT | Output breve al usuario |

**Reglas TDD que aplica**:
- Una behavior, un ciclo. No "horizontal slicing".
- Test debe fallar primero (true RED), no por syntax error
- Cada GREEN deja type-check + lint en 0
- Un commit por AC (commits atómicos)
- Si se rompe el scope, revierte el cambio extra

**Cadencia de commits**: uno por AC. Esto hace `git bisect` y review trivial.

---

### 4.2 `mr-multi-validate`

**Invocado desde**: `mr-issue-to-pr` step `validate`.

**Lee**: `$ARTIFACTS_DIR/implementation.md` + git diff.
**Escribe**: `$ARTIFACTS_DIR/validation.md`.

**Auto-detecta scope** del diff y corre solo los gates aplicables:

| Gate | Trigger | Qué corre |
|---|---|---|
| **CODE** | Siempre | Backend: ruff + ruff format --check + pytest. Frontend: tsc --noEmit + eslint + vitest |
| **HTTP** | Si `backend/app/(main\|api\|routers)` cambió | FastAPI TestClient: pega cada endpoint cambiado, verifica status code |
| **DOM** | Si `frontend/(components\|app)` cambió | vitest+jsdom sobre `.test.tsx` siblings de los componentes tocados |
| **STACK** | Si `docker*` o `Dockerfile` cambió | `docker compose config -q` + verifica build contexts |

**Failure strategy**: any gate ≠ 0 → command exits 1 → workflow halts. `create-pr` no se ejecuta con gates rojos.

**Por qué no `docker compose up`**: lento y flaky. El config-check + context-existence captura lo común (typos, missing dirs).

**Por qué generar el smoke test on-the-fly en HTTP**: el agente lee el diff, identifica los routes cambiados, escribe assertions específicos. No hay lista hardcoded.

---

### 4.3 `mr-promote-followups`

**Invocado desde**: `mr-issue-to-pr` step `promote-followups`.

**Lee**: `$ARTIFACTS_DIR/review/consolidated-review.md` + `$ARTIFACTS_DIR/review/fix-report.md`.
**Escribe**: `$ARTIFACTS_DIR/followups-report.md` + N GitHub issues nuevos.

**Lógica**:

1. Parsea el consolidated review y extrae findings MEDIUM y LOW
2. Excluye los que ya están en `fix-report.md` como FIXED
3. Filtra LOWs que son pura estética (rename de var local, etc.)
4. Mergea duplicados (mismo file:line, distintos agents)
5. Por cada finding: `gh issue create --label auto-followup` con body que linkea al PR origen
6. Comenta en el PR origen con la tabla completa de issues nuevos
7. Asegura el label `auto-followup` existe (lo crea si no)

**Cómo filtrar después**:
```bash
gh issue list --label auto-followup --state open
```

**Por qué solo MEDIUM/LOW**: el step previo `archon-implement-review-fixes` ya auto-fixea CRITICAL y HIGH. Este step toma el resto para que no se pierdan.

---

## 5. Artifact contracts

Los workflows pasan información entre nodos vía archivos en `$ARTIFACTS_DIR`. Esta es la convención completa:

| Archivo | Escrito por | Leído por |
|---|---|---|
| `investigation.md` | `archon-investigate-issue` (bugs) | `mr-tdd-implement`, `archon-pr-review-scope`, `archon-issue-completion-report` |
| `plan.md` | `archon-create-plan` (features) | `mr-tdd-implement` (vía bridge-artifacts), `archon-issue-completion-report` |
| `web-research.md` | `archon-web-research` | `archon-issue-completion-report` |
| `implementation.md` | `mr-tdd-implement` | `mr-multi-validate`, `create-pr`, `archon-issue-completion-report` |
| `validation.md` | `mr-multi-validate` | `create-pr`, `archon-issue-completion-report` |
| `.pr-number`, `.pr-url` | `create-pr` (workflow inline node) | `archon-pr-review-scope`, `mr-promote-followups`, `archon-issue-completion-report` |
| `review/scope.md` | `archon-pr-review-scope` | review agents, `archon-synthesize-review` |
| `review/{agent}-findings.md` | cada review agent | `archon-synthesize-review` |
| `review/consolidated-review.md` | `archon-synthesize-review` | `archon-implement-review-fixes`, `mr-promote-followups`, `archon-issue-completion-report` |
| `review/fix-report.md` | `archon-implement-review-fixes` | `mr-promote-followups`, `archon-issue-completion-report` |
| `followups-report.md` | `mr-promote-followups` | `archon-issue-completion-report` |
| `prds/{slug}.prd.md` | `mr-idea-to-prd` step `generate` | `mr-idea-to-prd` step `validate`, `post-to-github` |
| `slices.md` | `mr-prd-to-issues` step `refine-slices` | `mr-prd-to-issues` step `create-issues` |
| `.tdd-behaviors.md` | `mr-tdd-implement` Phase 2 | `mr-tdd-implement` Phase 3 (interno) |

**Convención de "scratchpad" (dot-prefixed)**: archivos como `.pr-number`, `.tdd-behaviors.md`, `.followups.json` son datos intermedios. Los `.md` sin dot son para humanos / posteo a GitHub.

---

## 6. Reused Archon defaults

Estos commands vienen con Archon (no los copies — están en el bundle global). El kit los referencia desde los workflows:

| Default command | Usado en | Para qué |
|---|---|---|
| `archon-web-research` | mr-issue-to-pr | Búsqueda externa para el contexto del issue |
| `archon-investigate-issue` | mr-issue-to-pr (cuando bug) | Root cause analysis con 5 Whys |
| `archon-create-plan` | mr-issue-to-pr (cuando feature) | Plan de implementación con codebase exploration |
| `archon-pr-review-scope` | mr-issue-to-pr | Manifest del PR para review |
| `archon-code-review-agent` | mr-issue-to-pr | Review de code quality + CLAUDE.md compliance |
| `archon-error-handling-agent` | mr-issue-to-pr | Review de manejo de errores |
| `archon-test-coverage-agent` | mr-issue-to-pr | Review de coverage (busca casos sin test) |
| `archon-comment-quality-agent` | mr-issue-to-pr | Review de calidad de comments/docstrings |
| `archon-docs-impact-agent` | mr-issue-to-pr | Review de impacto en docs externas |
| `archon-synthesize-review` | mr-issue-to-pr | Consolida los 5 reportes en CRITICAL/HIGH/MEDIUM/LOW |
| `archon-implement-review-fixes` | mr-issue-to-pr | Auto-fixea CRITICAL/HIGH (commit + push) |
| `archon-issue-completion-report` | mr-issue-to-pr | Reporte final al issue origen |

Si Archon actualiza estos defaults, te beneficiás automáticamente sin tocar el kit.

---

## 7. Customization recipes

### Cambiar el modelo del implement step

En `.archon/workflows/mr-issue-to-pr.yaml`, encontrá:

```yaml
- id: implement
  command: mr-tdd-implement
  model: claude-opus-4-6[1m]    # ← cambiá acá
```

Opciones:
- `claude-opus-4-7` — más capaz, más caro
- `claude-sonnet-4-6` — más barato, menos capaz
- `claude-opus-4-6[1m]` — actual (1M context)

### Agregar un quinto gate al multi-validate

Editá `.archon/commands/mr-multi-validate.md`. Agregá una `## Phase X: NUEVO GATE` con:
1. Trigger condition (qué tipo de cambio activa el gate)
2. Comandos a correr
3. Captura de exit code
4. Sumar al `OVERALL` aggregate

### Cambiar el threshold de auto-fix (CRITICAL/HIGH only → CRITICAL only)

Esto es una decisión de Archon's `archon-implement-review-fixes`, no del kit. Para overridear: copiá ese comando de Archon defaults a `.archon/commands/archon-implement-review-fixes.md` y editá.

### Agregar un step de Slack notification al final

Después de `report`, agregá un nodo:

```yaml
- id: notify-slack
  bash: |
    curl -X POST $SLACK_WEBHOOK -d '{"text":"PR ready: $(cat $ARTIFACTS_DIR/.pr-url)"}'
  depends_on: [report]
```

### Cambiar el label del auto-followups

En `.archon/commands/mr-promote-followups.md`, busca todas las apariciones de `auto-followup` y cambialas. Cambiá también el `gh label create auto-followup` por el nuevo nombre.

---

## 8. Troubleshooting

### "Skill 'tdd' not found in .claude/skills/"

Workflow validation warning. Significa que `.claude/skills/tdd/` no existe en tu repo (o en `~/.claude/skills/tdd/`). Copiá la skill del kit.

### "Command 'mr-xxx' not found"

```bash
archon validate workflows mr-issue-to-pr
```

Te dirá qué command falta. Verificá que el archivo `.md` exista en `.archon/commands/`.

### "MCP config file not found: .archon/mcp/ntfy.json"

Es un warning del default `archon-smart-pr-review`, NO de nuestro kit. Lo podés ignorar (ese workflow no lo usamos).

### El loop `refine-slices` no termina nunca

El usuario tiene que decir explícitamente "approved" / "looks good" / "ship it". Cualquier feedback distinto sigue el loop. Si querés cancelar:
```bash
archon workflow reject <run-id>
```

### `mr-multi-validate` falla porque pytest no encuentra deps

El step de DEPENDENCIES en `mr-tdd-implement` debería instalarlas. Si falla por venv: borrá el worktree, corré:
```bash
archon isolation cleanup
archon workflow run mr-issue-to-pr --branch fix/issue-N --resume "Fix issue #N"
```

### Quiero ver qué hizo cada step de un run que ya terminó

```bash
archon workflow status <run-id>
ls ~/.archon/workspaces/{owner}/{repo}/runs/<run-id>/
cat ~/.archon/workspaces/{owner}/{repo}/runs/<run-id>/implementation.md
```

### Re-correr solo desde un step que falló

```bash
archon workflow run mr-issue-to-pr --branch fix/issue-N --resume "..."
```

Esto skipea los nodes que ya completaron y arranca desde el primero pendiente.

### Lancé 5+ `mr-issue-to-pr` en paralelo con el script bash y mi compu se prendió fuego

Cada `mr-issue-to-pr` corre opus 4.6 en 1M context. Podés:
1. Reducir el modelo en `mr-issue-to-pr.yaml` (cambiar a sonnet en el step `implement`)
2. Reducir el cap de paralelismo en `~/.archon/.env`: `MAX_CONCURRENT_CONVERSATIONS=2`
3. Lanzar los hijos secuencialmente (sin `&` al final del comando) en el for-loop del script

### Workflow `mr-issue-to-pr` quedó como zombie (status running pero sin proceso)

Síntoma: `archon workflow status` o la DB muestran `running`, pero `ps aux | grep "archon workflow run mr-issue-to-pr"` no encuentra nada.

**Cancelarlo:**

```bash
# Encontrar los zombies (running >5 min sin procesos vivos)
sqlite3 -column -header ~/.archon/archon.db \
  "SELECT id, user_message, last_activity_at FROM remote_agent_workflow_runs \
   WHERE status='running' AND last_activity_at < datetime('now', '-5 minutes')"

# Cancelar los IDs encontrados
sqlite3 ~/.archon/archon.db \
  "UPDATE remote_agent_workflow_runs SET status='cancelled', completed_at=datetime('now') \
   WHERE id IN ('<id1>', '<id2>', ...)"

# Limpiar los worktrees
git worktree remove ~/.archon/workspaces/.../task-fix-issue-N --force
git branch -D archon/task-fix-issue-N
```

Causa más común: orquestador padre matado (timeout, ctrl+C, archon CLI crash) que dejó los hijos huérfanos. El script `nohup ... &` de la sección 3.5 evita este problema porque cada hijo es top-level.

---

## 9. Apéndice: Comandos útiles

```bash
# Listar workflows visibles
archon workflow list

# Validar todo
archon validate workflows
archon validate commands

# Listar runs activos
archon isolation list

# Limpiar worktrees viejos
archon isolation cleanup --merged
archon isolation cleanup       # default: 7 días

# Ver labels que el kit espera/crea
gh label list | grep -E '^(prd|auto-followup|HITL|AFK)\b'

# Filtrar issues del kit
gh issue list --label prd
gh issue list --label AFK --state open
gh issue list --label HITL
gh issue list --label auto-followup

# Cancelar un run
archon workflow reject <run-id>

# Ver el último PR creado por mr-issue-to-pr
gh pr view $(cat ~/.archon/workspaces/*/runs/*/.\.pr-number 2>/dev/null | tail -1)
```

---

*Kit autorado para el cradle-to-PR pipeline. Forkeado de Archon defaults con 3 customizaciones quirúrgicas.*
