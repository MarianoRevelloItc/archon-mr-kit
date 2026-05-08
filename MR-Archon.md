# MR-Archon — kit de workflows mr-* sobre Archon CLI

> Manual del kit de workflows custom (`mr-*`) corriendo sobre Archon. Para operación del producto Sales-Finder, ver `OPERATIONS.md`.
>
> El kit está en `.archon/workflows/` (YAMLs) y `.archon/commands/` (markdown commands).

---

## 0. Setup primera vez de un repo

```bash
archon workflow run mr-bootstrap-project --branch chore/bootstrap "Bootstrap"
```

Crea labels GitHub (`prd`, `auto-followup`, `HITL`, `AFK`, `needs-human-review`), `CLAUDE.md`, PR template, refina `.gitignore`.

---

## 1. Workflows del kit (mr-*)

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

## 2. `mr-issue-to-pr` paso a paso

Toma un issue de GitHub y produce un PR draft listo para review humano. **Vos mergeás manual.**

### Fases (16 nodos en total)

| # | Nodo | Modelo / Tipo | Qué hace |
|---|---|---|---|
| 1 | `extract-issue-number` | haiku | Extrae el `#N` desde el mensaje del usuario (o busca con `gh issue list` si es ambiguo) |
| 2 | `fetch-issue` | bash | `gh issue view N` → trae title, body, labels, comments |
| 3 | `classify` | haiku | Clasifica: `bug` / `feature` / `enhancement` / `refactor` / `chore` / `documentation` |
| 4 | `web-research` | command | Busca contexto en la web sobre el problema (paralelo con paso 5) |
| 5a | `investigate` | command | **Solo si `bug`** → investiga causa raíz, escribe `investigation.md` |
| 5b | `plan` | command | **Solo si NO es bug** → diseña approach, escribe `plan.md` |
| 6 | `bridge-artifacts` | bash | Normaliza: si hay `plan.md` y no `investigation.md`, lo copia |
| 7 | `implement` | **opus** + tdd skill | `mr-tdd-implement`: TDD estricto (red→green por cada AC), commitea |
| 8 | `validate` | command | `mr-multi-validate`: 4 gates en paralelo — CODE (lint+tests), HTTP (server arranca), DOM (frontend renderiza), STACK (deps OK) |
| 9 | `create-pr` | claude | Pushea branch, crea PR **draft**, llena PR template con `implementation.md` + `validation.md` |
| 10 | `review-scope` | command | Analiza el diff del PR para decidir qué reviewers correr |
| 11 | `review-classify` | haiku | Boolean por cada review agent: code/error-handling/test-coverage/comment-quality/docs-impact |
| 12 | 5 review agents | command (paralelo) | `code-review` (siempre) + 4 condicionales según paso 11 |
| 13 | `synthesize` | command | Consolida findings de los reviewers en `consolidated-review.md` con severity (CRITICAL/HIGH/MEDIUM/LOW) |
| 14 | `self-fix` | command | Implementa **automáticamente solo CRITICAL y HIGH** (los grave que rompen funcionalidad) |
| 15 | `promote-followups` | command | **MEDIUM y LOW → issues nuevos** con label `auto-followup` (no se fixean ahora, quedan trackeados) |
| 16 | `report` | command | Postea comment final al issue original con resumen + link al PR |

### Resultado al final

- PR **en estado draft** (no mergeado)
- Tiene el PR template completo (AC coverage table + validation gates)
- CRITICAL/HIGH del review ya están fixeados
- MEDIUM/LOW quedaron como issues nuevos con label `auto-followup`
- Vos abrís el PR, revisás los comments del reviewer, marcás "ready for review", mergeás manual

---

## 3. `mr-issue-to-pr-ralph` paso a paso

**Mismo DAG que `mr-issue-to-pr` con 2 nodos extra al final** que automatizan el merge cuando es seguro.

### Diferencias vs simple

```
mr-issue-to-pr:    [1..8] → create-pr → [10..16]
mr-issue-to-pr-ralph: [1..8] → rebase-against-main → create-pr → [10..16] → auto-merge-or-defer
                              ↑↑↑ NUEVO                                       ↑↑↑ NUEVO
```

### Nodos adicionales

| # | Nodo | Posición | Qué hace |
|---|---|---|---|
| **8.5** | `rebase-against-main` | Después de `validate`, antes de `create-pr` | Hace `git fetch origin main` + `git rebase origin/main`. Si hay conflict, falla acá (no rompe nada en main). Defensa contra runs paralelos / stale branches |
| **17** | `auto-merge-or-defer` | Después de `report` | Evalúa la threshold de merge — mergea o difiere |

### Política del nodo `auto-merge-or-defer` (BALANCED)

Mergea el PR (`gh pr merge --squash --delete-branch`) si **TODAS** estas condiciones se cumplen:

| Gate | Criterio |
|---|---|
| Validate (multi-layer) | CODE + HTTP + DOM + STACK gates en verde |
| CRITICAL findings pendientes | 0 (los que hubiera, `self-fix` los arregló) |
| Rebase against main | OK (sin conflicts contra main al momento del PR) |

Si **alguna falla** → NO mergea, agrega label `needs-human-review` al PR + comenta explicando qué gate fue el bloqueante.

### Cuándo usar cuál

| Situación | Workflow |
|---|---|
| AFK (te vas, querés que mergee solo si está limpio) | `mr-issue-to-pr-ralph` |
| Querés revisar/aprobar todo manual independientemente del resultado | `mr-issue-to-pr` |
| Quiero probar el batch (paralelo o secuencial) | `mr-issue-to-pr-ralph` (siempre) |

> **Tip:** ralph es estrictamente **≥ simple**. En el peor caso (PR no cumple threshold) ralph defiere y queda en el mismo estado que simple — vos mergeás manual. En el mejor caso, ya está mergeado cuando volvés. No hay escenario donde simple sea mejor.

---

## 4. Comandos `archon` CLI — referencia completa

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

Lo correcto: revisás el PR, los comments del reviewer (`consolidated-review.md`), y mergeás manual:

```bash
gh pr view <pr-num>
gh pr view <pr-num> --comments
# Si todo OK:
gh pr merge <pr-num> --squash --delete-branch
```

Si no querés mergearlo: `gh pr close <pr-num>` con comment explicando.

### `MAX_CONCURRENT_CONVERSATIONS` saturado (paralelismo)

Si saturás el rate limit del LLM o de Brave en runs paralelos: bajá `MAX_CONCURRENT_CONVERSATIONS` en `~/.archon/.env`.

---

## 6. Apéndice: comandos de uso frecuente del kit

```bash
# Estado del kit
archon workflow list 2>&1 | grep -E '^\s+mr-'
archon validate workflows 2>&1 | grep -E '^\s+mr-'
archon validate commands 2>&1 | grep -E '^\s+mr-'

# Filter issues por label del kit
gh issue list --label AFK --state open
gh issue list --label HITL
gh issue list --label needs-human-review --state open
gh issue list --label auto-followup --state open

# PRs creados por el kit hoy
gh pr list --search "head:fix/issue- created:>=$(date -v-1d +%Y-%m-%d)" \
  --json number,title,state,mergedAt --jq '.[] | "  PR #\(.number) [\(.state)] \(.title)"'

# Cleanup post-sprint
archon isolation cleanup --merged
gh pr list --state closed --search "merged:>=$(date -v-7d +%Y-%m-%d)" \
  --json number,title --jq '.[] | "#\(.number): \(.title)"'
```

---

## 7. Testing scaffold (estado de roadmap)

Patrón que el kit `mr-*` espera para que `pytest` colecte tests dentro de worktrees aislados y para que las próximas fases (VCR / Vitest+MSW / Playwright) tengan donde apoyarse.

### Estado actual: Fase 1 implementada manual

Hoy son **4 archivos por proyecto**, escritos a mano sobre la estructura existente. La Fase 5 los va a templatizar dentro de `mr-bootstrap-project` (ver "Roadmap" más abajo).

#### 1. `backend/.env.test` (commiteado)

Dummies para que Pydantic Settings instancie sin error en worktrees limpios. **No se usan para llamadas reales** — solo pasan validación.

```
DATABASE_URL=postgresql://test:test@localhost:5432/test_db
BRAVE_SEARCH_API_KEY=test-brave-key
GEMINI_API_KEY=test-gemini-key
LLM_ANALYSIS_MODEL=claude-haiku-4-5-20251001
LLM_JUDGMENT_MODEL=claude-sonnet-4-6
GOOGLE_MAIL_API_KEY=test-gmail-key
GMAIL_FROM_ADDRESS=test@example.com
ENVIRONMENT=test
```

> Adaptar a las env vars que tu `Settings` requiera (mirar `app/config.py`).

#### 2. `backend/tests/conftest.py`

Carga `.env.test` antes de cualquier `import app.*`. `override=False` para que vars reales en shell ganen.

```python
"""pytest config — load .env.test before any app imports."""

from pathlib import Path
from dotenv import load_dotenv

_ENV_TEST = Path(__file__).parent.parent / ".env.test"
load_dotenv(_ENV_TEST, override=False)
```

#### 3. `backend/app/config.py` — `env_file` con path absoluto

`env_file=".env"` (relativo) depende del CWD donde corra Python. Frágil. Anclar al directorio del módulo:

```python
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_BACKEND_ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", env_file=_BACKEND_ROOT / ".env")
    # ...
```

#### 4. `backend/tests/test_config_loading.py` (opcional pero recomendado)

3 tests que verifican el patrón aplicado correctamente. Útil porque si alguien rompe la cadena (borra `.env.test`, elimina `env_file=` del `Settings`, etc.) los gates lo cazan.

```python
"""Tests for config loading — verifies .env.test + conftest unblock collection."""

from pathlib import Path


def test_env_test_file_exists():
    env_test = Path(__file__).parent.parent / ".env.test"
    assert env_test.exists(), ".env.test missing — worktree pytest collection will fail"


def test_settings_configdict_uses_absolute_env_file():
    from app.config import Settings

    env_file = Settings.model_config.get("env_file")
    assert env_file is not None
    env_path = Path(env_file)
    assert env_path.is_absolute()
    assert env_path.name == ".env"


def test_conftest_loads_env_test_with_override_false():
    from app.config import settings

    assert settings.DATABASE_URL, "DATABASE_URL empty — conftest likely failed to load .env.test"
```

### Verificación

En un clone limpio (sin `.env`):
```bash
cd backend
pytest --collect-only        # NO debe dar ValidationError
pytest tests/test_config_loading.py -v   # 3/3 verde
```

### Tests integration (issue #72)

Los tests que requieren un Postgres real (con data seedeada) están marcados con `@pytest.mark.integration` (a nivel de módulo: `pytestmark = pytest.mark.integration`). Por default `pytest` los **excluye** (configurado en `pyproject.toml: addopts = "-m 'not integration'"`).

```bash
# Default (lo que corre mr-multi-validate en archon worktrees) — solo unit/mock-based
cd backend
uv run pytest -q

# Cuando docker-compose está up con la DB seedeada — corre TODO incluido integration
docker compose exec backend pytest -q -m integration
```

**Archivos marcados como integration** (hoy): `test_endpoints.py`, `test_models.py`, `test_sprint6.py`, `test_wichita.py`, `test_ingest_addapt.py`, `test_user_actions.py`.

### Roadmap (próximas fases)

| Fase | Qué agrega | Estado |
|---|---|---|
| **1** | `.env.test` + `conftest.py` + abs path en `Settings` | ✅ implementada (Sales-Finder PR #63) |
| 2 | `pytest-recording` + cassettes VCR para Brave/Anthropic/HTTP externo | 📋 pendiente |
| 3 | `vitest.config.ts` + MSW handlers para tests de componentes frontend | 📋 pendiente |
| 4 | `playwright.config.ts` + e2e specs para flujos golden path | 📋 pendiente |
| **5** | **Phase nueva en `mr-bootstrap-project`** que escribe Fases 1-4 sobre cualquier repo nuevo (idempotente) | 📋 pendiente |

Hasta que Fase 5 esté lista, **cada repo nuevo aplica Fase 1 manual** copiando los 4 snippets de arriba. Cuando Fase 5 mergee, `archon workflow run mr-bootstrap-project` los va a sembrar automático.

---

*Última actualización: 2026-05-04. Si encontrás un comando que falta o un troubleshoot que repetiste 2+ veces, agrégalo acá.*
