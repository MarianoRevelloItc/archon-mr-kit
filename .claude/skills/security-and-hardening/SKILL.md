---
name: security-and-hardening
description: Use when implementing or reviewing authentication flows, handling secrets, validating inputs, auditing dependencies, or before deploying to production. Triggers on auth/JWT/session/CSRF/OWASP/secret/credential/audit terms in the request, or any code touching login, signup, password handling, token issuance, role checks, or env-var-loaded credentials.
---

# Security and Hardening

## When this skill applies

- Implementing or modifying: authentication, authorization, session handling, password storage, token issuance/verification, CSRF protection, role/permission checks.
- Handling: secrets, credentials, API keys, environment variables, certificates, signing keys.
- Validating: any input that crosses a trust boundary (HTTP request body/query/headers, file uploads, deserialization, SQL parameters, shell command arguments).
- Reviewing: a PR that touches any of the above.
- Pre-deploy: when the next step is shipping code to a production environment.

If none of the above apply, **don't load this skill**. Security work in the wrong context produces paranoid noise.

---

## The 5 axes

Every security review covers these five surfaces. Walk them in order — earlier failures often imply later ones.

### Axis 1: Input validation

Every byte that crosses a trust boundary is hostile until proven otherwise.

- **HTTP inputs**: validate body / query / path / headers against a typed schema (Pydantic, Zod, JSON Schema). Reject on parse failure with a 4xx — never `try: ... except: pass`.
- **SQL**: parameterized queries only. Never concat user input into SQL strings, even "safe-looking" ones (numbers, enums).
- **Shell**: never pass user input to `subprocess.run(shell=True)`, `os.system`, or `child_process.exec`. Use the array form (`subprocess.run([...])`) and validate each arg.
- **Deserialization**: never `pickle.loads`, `yaml.load` (use `yaml.safe_load`), `eval`, `Function(...)` on untrusted data.
- **File paths**: reject `..`, absolute paths, symlinks where unexpected. Validate against an allowlist of dirs.
- **Output encoding**: HTML-escape user content rendered into pages; JSON-encode it into APIs. Don't `dangerouslySetInnerHTML` (React) or `v-html` (Vue) on user content.

### Axis 2: Authentication and session

- **Passwords**: hash with bcrypt/argon2id with a non-trivial cost. Never store plaintext, never use MD5/SHA-1, never use a homemade scheme.
- **Tokens**: prefer short-lived JWTs with refresh tokens (rotated) OR server-side sessions. Never put secrets in the JWT payload — payload is signed, not encrypted.
- **CSRF**: state-changing endpoints over cookies need a CSRF token (double-submit cookie or SameSite=Strict + Origin check). Token-based auth via Authorization header is CSRF-immune.
- **Session fixation**: rotate session ID on login.
- **Logout**: invalidate the session server-side, not just client-side.
- **Rate limit**: login, password reset, token issuance — at least IP+account level.

### Axis 3: Secrets and credentials

- **Never in git**: no API keys, no DB passwords, no signing keys, no `.env` files (commit `.env.example` with empty values).
- **Never in logs**: scrub `password`, `token`, `secret`, `key`, `authorization` keys before logging. Test that error responses don't leak them in stack traces.
- **Never in client-side code**: anything in JavaScript bundles is public. Use a backend proxy for any third-party API that has a real key.
- **Storage**: env vars in a managed secret store (Vault, AWS Secrets Manager, Doppler). For local dev: `.env` in `.gitignore`.
- **Rotation**: any leaked credential is rotated within 1 hour of detection. Have the rotation procedure documented in `docs/runbook/INCIDENT.md`.

### Axis 4: Dependencies

- **Audit on every PR**: `pip-audit` (Python), `npm audit --production` (Node), `cargo audit` (Rust). Fail the PR on HIGH/CRITICAL CVEs in production deps.
- **Pin versions**: `requirements.txt` pinned, `package-lock.json` / `uv.lock` committed. No `^` or `~` ranges in production paths.
- **Trim deps**: each new dep is a new attack surface. Reject deps that pull > 50 transitive deps for a small feature.
- **Watch supply chain**: typosquatting, dependency confusion, malicious publishes. Tools: Socket.dev, Snyk.

### Axis 5: Observability

- **Log auth events**: login success/fail, password reset, token issuance, role change, admin action. Include user ID, IP, timestamp, action.
- **Alert on anomalies**: 5+ failed logins in a minute, login from a new geo, sudden privilege escalation.
- **Don't log PII unnecessarily**: emails are PII in some jurisdictions; full request bodies often contain PII.
- **Audit trail**: who changed what when. Append-only — no UPDATE/DELETE on the audit log table.

---

## Anti-rationalization table

When you catch yourself thinking the left column, the right column is the truth.

| You're thinking | The reality |
|-----------------|-------------|
| "I'll handle this in next sprint." | Security debt accumulates as compound interest. The cost to fix later is 10× the cost to fix now. Most production breaches trace to a "next sprint" fix. |
| "This endpoint is internal — no need to validate." | "Internal" is a perimeter assumption that breaks the moment you misconfigure a network policy or someone runs a feature flag rollout. Validate every input. |
| "We'll add rate limiting later." | Brute-force scripts run at 1000+ req/sec. By the time "later" arrives, an attacker has cracked the weak passwords. |
| "Logging the token helps debugging." | Logs leak. Tokens in logs are equivalent to tokens in plaintext storage. Use a redacted hash if you need to correlate. |
| "It's just for staging." | Staging gets deployed to. Staging gets backups. Staging passwords get reused. Same standards everywhere. |
| "The library handles security." | Libraries handle the *typical* case. Misconfiguration (default secret keys, debug=True in prod, permissive CORS) is the #1 way library-protected apps get breached. |
| "I know this is safe — I read the code." | Threat model > intuition. Write the test that proves invalid input is rejected. |
| "OWASP feels paranoid." | OWASP Top 10 is empirical — those ARE the most exploited classes of bug. If your code doesn't address one, you're betting on luck. |
| "Pip-audit found 17 CVEs but they're all in dev deps." | Dev deps run on developers' laptops with cookies, SSH keys, AWS creds. Compromised dev = compromised prod. Audit them too. |

---

## Quick checklist (pre-deploy)

Run mentally before merging anything that touches an external surface:

```
[ ] Every HTTP input goes through a typed schema validator
[ ] Passwords stored with bcrypt/argon2id (cost ≥ 10)
[ ] CSRF token on every state-changing cookie endpoint
[ ] No secrets in git history (run `git secrets --scan` or trufflehog)
[ ] No secrets in logs (search the log file for KEY/TOKEN/PASSWORD)
[ ] Dependency audit clean (no HIGH/CRITICAL in prod deps)
[ ] Rate limits on /login, /signup, /password-reset, /token
[ ] HTTPS enforced (HSTS header, redirect HTTP → HTTPS)
[ ] CSP header set (no `unsafe-inline` or `unsafe-eval` in script-src)
[ ] CORS origin allowlist is explicit (no `*` for credentialed endpoints)
[ ] Auth events logged with user ID + IP + timestamp
```

---

## When in doubt

Cite OWASP. The [OWASP Top 10](https://owasp.org/www-project-top-ten/) is the empirical baseline — if your code doesn't address each item, document why in an ADR (`documentation-and-adrs` skill).

For deep review of high-risk PRs, invoke the `security-auditor` persona via the `mr-deep-review` command — it runs in a fresh context window with a stricter system prompt.
