# OPERATIONS — Sales-Finder runbook

> Manual operacional para correr el producto y el kit de workflows.
> Para uso del kit (PRD → issue → PR), ver `New_Project/MANUAL.md`.

---

## 0. Setup inicial

### Pre-requisitos

```bash
# Tools requeridas (instalar una vez por máquina)
git --version       # cualquier versión moderna
gh --version        # GitHub CLI, autenticado
gh auth status      # debe mostrar logged in

archon version      # CLI de Archon
docker --version
docker compose version
```

### Levantar el stack local

```bash
cd "/Users/mariano/Documents/Trabajo/IT Crowd/Proyectos ITC/Sales-Finder"

# 1. Variables de entorno
cp .env.example .env  # editar con keys reales (BRAVE_SEARCH_API_KEY, etc.)

# 2. Up
docker compose up -d

# 3. Verificar
docker compose ps
docker compose logs -f backend  # debería arrancar sin errores
```

### Setup primera vez de un repo nuevo

```bash
archon workflow run mr-bootstrap-project --branch chore/bootstrap "Bootstrap"
```

Crea labels GitHub (`prd`, `auto-followup`, `HITL`, `AFK`, `needs-human-review`), `CLAUDE.md`, PR template, refina `.gitignore`.

---

## 1. Workflows del kit (mr-*) — auto-implementación

Para implementar issues, agregar features, splitear PRDs, etc.

| Workflow | Cuándo usarlo | Tiempo | AFK? |
|---|---|---|---|
| `mr-idea-to-prd` | Idea fuzzy → PRD como GitHub issue | ~30-60 min | ❌ interactivo (3 gates de preguntas) |
| `mr-prd-to-issues` | PRD issue → N child issues con label AFK/HITL | ~10-15 min | ❌ semi-interactivo (loop hasta aprobar) |
| `mr-issue-to-pr` | 1 issue → PR draft (vos mergeás manual) | ~15-90 min | ✅ implementación, ❌ merge manual |
| `mr-issue-to-pr-ralph` | 1 issue → PR + auto-merge si threshold OK | ~15-90 min | ✅ AFK total |
| `mr-plan-waves` | N issues → analiza overlap → genera 2 scripts (seq + par) | ~10-20 min | ✅ read-only |
| `mr-bootstrap-project` | Setup inicial de un repo nuevo | ~2 min | ✅ |

### Comandos copy-paste

```bash
# 1 issue manual (vos mergeás)
archon workflow run mr-issue-to-pr --branch fix/issue-N "Fix issue #N"

# 1 issue AFK (auto-merge si threshold OK)
archon workflow run mr-issue-to-pr-ralph --branch fix/issue-N "Fix issue #N"

# N issues secuencial (más seguro, sin conflicts)
for n in 2 4 5; do
  archon workflow run mr-issue-to-pr-ralph --branch "fix/issue-$n" "Fix issue #$n"
done

# N issues paralelo (más rápido, riesgo de conflicts)
for n in 2 4 5; do
  nohup env -u CLAUDECODE archon workflow run mr-issue-to-pr-ralph \
    --branch "fix/issue-$n" "Fix issue #$n" \
    > "/tmp/mr-batch-logs/issue-$n.log" 2>&1 &
  disown $!
  sleep 5
done

# N issues con plan inteligente (analiza overlap, genera scripts seq + par)
archon workflow run mr-plan-waves --branch plan/sprint "Plan #2 #4 #5 #7 #8"
# Después correr UNO de los scripts generados:
nohup bash /tmp/mr-plan-{timestamp}/run-parallel.sh > /tmp/wave.log 2>&1 &
disown $!
```

### Política de auto-merge del ralph

Mergea el PR al final si **todas** las gates pasan:

| Gate | Criterio |
|---|---|
| Validate (multi-layer) | CODE + HTTP + DOM + STACK gates en verde |
| CRITICAL findings | 0 pendientes (los que haya, el self-fix los arregló) |
| Rebase against main | OK (sin conflicts contra main al momento del PR) |

Si NO cumple → label `needs-human-review` + comment al PR explicando por qué.

### El flujo idea → producción

```
mr-idea-to-prd (idea fuzzy)
     ↓
   PRD issue (label `prd`)
     ↓
mr-prd-to-issues (split en vertical slices)
     ↓
   N child issues (label AFK o HITL)
     ↓
mr-plan-waves (opcional — analiza overlap si N > 5)
     ↓
mr-issue-to-pr-ralph (por cada issue AFK)
     ↓
   N PRs (auto-merged limpios, otros como needs-human-review)
```

---

## 2. Comandos `archon` CLI — referencia completa

### `archon workflow`

```bash
# Listar workflows disponibles (defaults + custom del repo)
archon workflow list
archon workflow list --json                  # output machine-readable

# Correr un workflow
archon workflow run <name> --branch <branch> "<message>"
archon workflow run <name> "<message>"        # sin branch → archon auto-genera

# Flags útiles:
#   --branch, -b <name>      Crea worktree aislado (default behavior recomendado)
#   --no-worktree            Corre sobre branch actual sin isolation (riesgoso)
#   --resume                 Resume del último run fallido (skipea nodos completados)
#   --from <base-branch>     Crea desde una branch específica (default: main)
#   --cwd <path>             Override del working directory
#   --quiet, -q              Reduce log verbosity
#   --verbose, -v            Debug output

# Status de workflows corriendo
archon workflow status
archon workflow status <run-id>               # de un run específico
```

### `archon isolation` (worktrees)

```bash
# Listar worktrees activos
archon isolation list

# Limpiar worktrees viejos (default: > 7 días)
archon isolation cleanup
archon isolation cleanup 14                   # > 14 días
archon isolation cleanup --merged             # solo los con branch ya mergeada

# Completar lifecycle de un branch (worktree + branch local + remote)
archon complete <branch-name>
```

### `archon validate`

```bash
# Validar workflows (estructura YAML, refs a commands, etc.)
archon validate workflows                     # todos
archon validate workflows mr-issue-to-pr      # uno solo
archon validate workflows --json              # output machine-readable

# Validar commands (.md files en .archon/commands/)
archon validate commands
archon validate commands mr-tdd-implement
```

### `archon` general

```bash
archon chat "<message>"                       # mensaje al orchestrator
archon setup                                  # wizard interactivo de credenciales
archon serve                                  # arranca web UI server (descarga UI primera vez)
archon serve --port 4000                      # override puerto (default: 3090)
archon continue <branch> "<msg>"              # continúa work en un worktree existente con contexto
archon version                                # versión del CLI
archon help                                   # help general
```

### Cuándo usar cuál

| Situación | Comando |
|---|---|
| ¿Qué workflows tengo? | `archon workflow list` |
| Lanzar un workflow | `archon workflow run <name> --branch <b> "<msg>"` |
| ¿Está corriendo algo? | `archon workflow status` |
| ¿Cuántos worktrees vivos? | `archon isolation list` |
| Limpiar después de mergear PRs | `archon isolation cleanup --merged` |
| Verificar que el kit es válido | `archon validate workflows && archon validate commands` |
| Web UI para visualizar runs | `archon serve` (después abrir `localhost:3090`) |

---

## 3. Pipeline del producto

> **TEMPLATE — adaptar a tu proyecto**. Esta sección documenta los stages/scripts del producto que vivís en este repo. Reemplazá por los del tuyo. Para un ejemplo real con T0-T7, ver `Sales-Finder/OPERATIONS.md`.

### Plantilla recomendada de stages

Ordená tu pipeline de **barato/determinista → caro/LLM/search**. Cada stage filtra/enriquece la salida de la anterior.

| Stage | Qué hace (template) | Costo | Naturaleza |
|---|---|---|---|
| T1 | Ingestion / seed (scrape, API, CSV import) | scraping/API | Determinista |
| T2 | Filter categórico (reglas hard, NAICS, etc.) | código | Determinista |
| T3 | Filter inteligente (LLM clasifica por nombre/atributo) | LLM (haiku) | Sin search — barato |
| T4 | Enrichment (web search + LLM extrae datos) | LLM + search | Caro |
| T5 | Detect / classify (signals, scoring, etc.) | LLM + search + scraping | Más caro |
| T6 | Narrativa / output (prosa, summary) | LLM (sonnet) | Sin search |
| T7 | State / notifications (state machine + email/digest) | código | Determinista |

**Por qué este orden**: rebajás universo gradualmente. No gastes search en empresas que iban a descartarse por categoría.

### Comandos por stage (template)

```bash
# Convención: scripts en backend/scripts/<stage>.py
# Correr dentro del container o con venv local

docker compose exec backend python scripts/<stage_script>.py

# Ejemplo de cadena completa (encadenar con &&):
docker compose exec backend bash -c '
  python scripts/stage_1_ingest.py && \
  python scripts/stage_2_filter.py && \
  python scripts/stage_3_classify.py
'
```

### Documentar acá

Para cada stage real de tu proyecto, agregá:

- **Nombre del script**: `backend/scripts/<nombre>.py`
- **Qué consume** (tabla / state previo)
- **Qué produce** (campo / state nuevo)
- **Costos externos** (API calls, tokens, rate limits)
- **Idempotencia**: ¿se puede re-correr sin duplicar?
- **Ejecución típica**: cadencia (manual / scheduled)

### Jobs programados (template)

| Job | Cadencia | Comando | Stage que invoca |
|---|---|---|---|
| `<ej: digest diario>` | 9am | `python scripts/<job>.py` | T7 |
| `<ej: rescan semanal>` | Lunes | `python scripts/<job>.py --filter X` | T5 |
| `<ej: cleanup mensual>` | Día 1 | `python scripts/<job>.py` | T7 |

Implementación típica: APScheduler embebido en backend, o cron del sistema.

---

## 4. Verificación post-run

### ¿El backend está vivo?

```bash
curl http://localhost:<API_PORT>/health    # ej: 8000
# Esperado: {"status": "ok"} o similar
```

### ¿Cuántos elementos en cada estado del pipeline? (template)

```bash
docker compose exec backend python -c "
from app.database import SessionLocal
from app.models.<your_main_entity> import <YourEntity>
s = SessionLocal()
for state in ['<state1>', '<state2>', '<state3>']:
    n = s.query(<YourEntity>).filter_by(state=state).count()
    print(f'{state}: {n}')
"
```

### ¿Está mi caso canónico en el estado esperado? (template)

```bash
docker compose exec backend python -c "
from app.database import SessionLocal
from app.models.<your_entity> import <YourEntity>
s = SessionLocal()
e = s.query(<YourEntity>).filter(<YourEntity>.<key_field>.ilike('%<value>%')).first()
print(f'state: {e.state}')
"
```

### Frontend

```bash
open http://localhost:<FRONTEND_PORT>    # ej: 3000
# Verificá las views principales de tu app — kanban, dashboard, etc.
```

### PRs creados por el kit hoy

```bash
gh pr list --search "head:fix/issue- created:>=$(date -v-1d +%Y-%m-%d)" \
  --json number,title,state,mergedAt --jq '.[] | "  PR #\(.number) [\(.state)] \(.title)"'
```

---

## 5. Troubleshooting

### Workflow zombie (status `running` pero sin proceso)

```bash
# Listar zombies (running > 5 min sin actividad)
sqlite3 ~/.archon/archon.db "
  SELECT id, user_message, last_activity_at
  FROM remote_agent_workflow_runs
  WHERE status='running' AND last_activity_at < datetime('now', '-5 minutes')
"

# Cancelar
sqlite3 ~/.archon/archon.db "
  UPDATE remote_agent_workflow_runs
  SET status='cancelled', completed_at=datetime('now')
  WHERE id IN ('<id1>', '<id2>')
"

# Cleanup worktrees huérfanos
git worktree remove <path> --force
git branch -D <branch>
```

### Conflict de merge entre PRs hermanos

```bash
# Verificar archivos en conflicto
gh pr view <pr-num> --json mergeable,mergeStateStatus

# Resolución manual:
gh pr checkout <pr-num>
git fetch origin main
git rebase origin/main
# resolver conflicts en editor
git add -A && git rebase --continue
git push --force-with-lease
gh pr merge <pr-num> --squash --delete-branch
```

### Brave Search rate limit (429)

Tier gratis: 2,000 queries/mes, 1 QPS. El kit aplica retry automático en 429 con sleep 5s.

```bash
# Ver consumo del mes
# (manual via dashboard de Brave: https://api.search.brave.com/app/keys)
```

Si saturás: bajá `MAX_CONCURRENT_CONVERSATIONS` en `~/.archon/.env` para reducir paralelismo.

### Postgres se cae / corrupto

```bash
docker compose down
docker volume rm sales-finder_postgres_data    # ⚠️ destructivo — pierde data
docker compose up -d
# Re-correr migraciones
docker compose exec backend alembic upgrade head
```

### `archon workflow` no encuentra mr-* workflows

```bash
# Verificar que están en el repo (no solo localmente sin commitear)
ls .archon/workflows/
git log --oneline -- .archon/workflows/

# Si faltan: cherry-pick del reflog (pasó una vez 2026-05-04)
git reflog | grep -i "kit\|ralph\|plan-waves"
git cherry-pick <commit-id>
git push origin main
```

### Auto-merge del ralph dejó PR como `needs-human-review`

Lo correcto: revisás el PR, los comments del reviewer (consolidated-review.md), y mergeás manual:

```bash
gh pr view <pr-num>
gh pr view <pr-num> --comments
# Si todo OK:
gh pr merge <pr-num> --squash --delete-branch
```

Si no querés mergearlo: `gh pr close <pr-num>` con comment explicando.

---

## 6. Schedule de jobs background (production) — template

| Job | Cadencia | Comando | Stage |
|---|---|---|---|
| `<job_name>` | `<cron / cadencia>` | `python scripts/<job>.py` | `<stage>` |
| ... | ... | ... | ... |

Implementación típica: APScheduler dentro del proceso backend (`backend/app/scheduler.py` o similar) o cron del sistema host.

Ver `Sales-Finder/OPERATIONS.md` sección 6 para un ejemplo real.

---

## 7. Apéndice: comandos de uso frecuente

```bash
# Estado general del sistema
docker compose ps
gh issue list --state open
gh pr list --state open
archon isolation list
archon workflow list 2>&1 | grep -E '^\s+mr-'

# Filter labels
gh issue list --label AFK --state open
gh issue list --label HITL
gh issue list --label needs-human-review --state open
gh issue list --label auto-followup --state open

# Cleanup post-sprint
archon isolation cleanup --merged
gh pr list --state closed --search "merged:>=$(date -v-7d +%Y-%m-%d)" \
  --json number,title --jq '.[] | "#\(.number): \(.title)"'

# Quick sanity check del kit
archon validate workflows 2>&1 | grep -E '^\s+mr-'
archon validate commands 2>&1 | grep -E '^\s+mr-'
```

---

*Última actualización: 2026-05-04. Si encontrás un comando que falta o un troubleshoot que repetiste 2+ veces, agrégalo acá.*
