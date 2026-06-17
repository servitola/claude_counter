# Execution Plan: api-scraper

**Создан:** 2026-06-17
**Baseline:** `swift build` OK, `swift test` 50 passed / 7 suites (green).

**Стратегия:** реализация задач последовательно по зависимостям (надёжная
зелёная сборка, без гонок за `.build/` и git-индекс); ревью — параллельно
(ревьюеры только читают diff). Лид коммитит после каждой задачи.

---

## Wave 1 (независимые)

### Task 1: API models + JSON decoding + test fixtures
- **Skill:** code-writing · **Reviewers:** code-reviewer, test-reviewer

### Task 3: OrgIDStore (org uuid cache)
- **Skill:** code-writing · **Reviewers:** code-reviewer, test-reviewer

### Task 4: CookieBridge (read + write-back, host-scoped)
- **Skill:** code-writing · **Reviewers:** code-reviewer, security-auditor, test-reviewer

## Wave 2 (зависит от Wave 1)

### Task 2: limits[] → ClaudeUsage mapper
- **Skill:** code-writing · **Reviewers:** code-reviewer, test-reviewer · depends_on [1]

## Wave 3 (зависит от Wave 1+2)

### Task 5: UsageAPIClient (URLSession fetch + discovery + classification)
- **Skill:** code-writing · **Reviewers:** code-reviewer, security-auditor, test-reviewer · depends_on [1,2,3,4]
- **Verify-smoke:** harness fetch() → populated ClaudeUsage (URLSession, не curl)

## Wave 4 (зависит от Wave 3)

### Task 6: QuotaScraper orchestration (API-first, WebView fallback, backoff)
- **Skill:** code-writing · **Reviewers:** code-reviewer, test-reviewer · depends_on [5]
- **Verify-user:** запуск приложения, проверка меню-бара + памяти

## Wave 5 — Audit Wave (reviewers: none, аудиторы = ревью)

### Task 7: Code Audit · Task 8: Security Audit · Task 9: Test Audit
- depends_on [6]

## Wave 6 — Final Wave

### Task 10: Pre-deploy QA (`make ci` + acceptance criteria)
- depends_on [7,8,9]

## Проверки, требующие участия пользователя

- [ ] Task 6: запуск приложения залогиненным — меню-бар совпадает с claude.ai,
      Activity Monitor показывает память ниже ~82 MB без per-tick WebContent.
- [ ] Live-проверки (403→refresh, logout-backoff) — Cloudflare-gated,
      отложены на ручную/post-deploy верификацию.
</content>
