# decision-guard — Konsolidiertes Experten-Review

**Datum:** 2026-03-28
**Methode:** 4 unabhängige Spezialisten-Agents (AI Systems Architect, DX/Adoption Expert, SRE/Reliability Engineer, Product Strategist) haben das gesamte Plugin analysiert und kritisch bewertet.

---

## Gesamturteil

Das Plugin ist technisch solide, gut dokumentiert und löst ein reales Problem. Die Kern-Architektur (Skills + Hooks, zero dependencies, Markdown + YAML) ist richtig. Aber es gibt kritische Lücken in Skalierung, Adoption und Team-Nutzung, die die praktische Wirksamkeit begrenzen.

---

## KRITISCH — Muss gefixt werden

### 1. Context Death Spiral bei Skalierung

**Quellen:** AI Architect, DX Expert

`session-start.sh` injiziert ALLE aktiven Decisions komplett — inklusive Decision, Rationale, Alternatives, Consequences, Change Warning. Bei 30+ Decisions sind das 15.000-20.000 Tokens, bevor der User überhaupt tippt. Nach Context-Compaction wird alles sofort re-injiziert, was den Context schneller füllt als zuvor.

**Impact:** Performance-Degradation und Context-Verdrängung. Claude hat weniger Platz für die eigentliche Aufgabe.

**Fix:**
- Session-start injiziert nur ID + Titel + Change Warning (1 Zeile pro Decision)
- Voller Content nur via `prompt-check.sh` bei Keyword-Match
- Hard-Cap bei 30 aktiven Decisions mit Warnung ("Run /decision-guard:review to prune")
- Check-Skill: Two-Pass — erst Frontmatter scannen, voller Content nur bei Scope/Keyword-Match

---

### 2. Stop-Hook False Positives töten die Adoption

**Quellen:** DX Expert, Product Strategist

Die Decision-Worthy-Heuristik ist zu grob. Szenarien die fälschlich blockieren:
- 3 neue Component-Dateien für ein Routine-Feature (kein Design-Choice)
- Version-Bump in package.json
- 8 Renames ohne architektonische Bedeutung
- Gelöschte Test-Fixtures

User lernen innerhalb einer Woche den Doppel-Tap (Escape Hatch), was den Enforcement-Mechanismus aushebelt.

**Impact:** User deaktivieren Hooks oder ignorieren den Block reflexartig. Das Plugin verliert seine Zähne.

**Fix:**
- Dateien innerhalb eines bestehenden Decision-Scopes als nicht-decision-worthy werten
- Version-Bumps und bekannte Routine-Patterns rausfiltern
- Shift von "block" (exit 2) zu "ask": Claude fasst die Änderungen zusammen und fragt ob geloggt werden soll
- Signal-to-Noise Tracking in `.decisions/.stats` um Heuristiken zu tunen

---

### 3. Semantische Lücke — 30-40% der echten Konflikte werden verpasst

**Quelle:** AI Architect

Keyword-Matching kann keine semantischen Gegensätze erkennen:

| User Prompt | Keyword-Hits | Erkannt? |
|-------------|-------------|----------|
| "Make the button like yesterday" | "button" (6 chars) | Ja |
| "Revert the UI to how it looked before" | "UI" (2 chars, weak) | Nein |
| "Go back to the old styling" | — | Nein |
| "The client wants the original look" | — | Nein |
| "Undo my last session's changes" | — | Nein |

Die CLAUDE.md-Regel (60-75% Compliance) ist die eigentliche Verteidigung, nicht die Hooks.

**Impact:** Stille Fehlschläge — der User vertraut dem System während Konflikte unerkannt durchgehen.

**Fix:**
- Universal-Conflict-Keywords automatisch zu jeder Decision: "revert", "undo", "go back", "original", "previous", "before", "old", "remove"
- Wenn diese Wörter im Prompt UND aktive Decisions existieren → injiziere alle Decisions
- Synonym-Generierung bei Log-Erstellung (3-5 Synonyme pro Keyword speichern)
- Scope-basierte PreToolUse-Prüfung stärken (Directory-Level Matching)
- Limitation ehrlich dokumentieren: Hooks sind supplementär, nicht die Hauptverteidigung

---

### 4. Team-Nutzung ohne Governance = Chaos

**Quellen:** DX Expert, Product Strategist

Szenarien die im Team-Alltag auftreten:
- Dev A loggt "Use Tailwind". Dev B loggt "Use CSS Modules". Beide mergen. Widerspruch.
- Kein `author`-Feld — "The user requested X" — welcher User?
- `conflicts_with` wird nie automatisch befüllt
- Git kann semantische Konflikte zwischen Decision-Dateien nicht erkennen
- Kein Approval-Workflow für team-weite Decisions

**Impact:** Das Journal wird eine Quelle der Verwirrung statt der Klarheit. Widersprüchliche Decisions akkumulieren.

**Fix:**
- `author`-Feld aus `git user.name` im log-Skill hinzufügen
- Session-start: widersprüchliche aktive Decisions erkennen (overlapping Scope ohne `conflicts_with` Referenz)
- `proposed` → `active` Status-Workflow für Team-Decisions (via PR-Review)
- Team-Workflow im README dokumentieren

---

### 5. First-Value Friction — Aha-Moment kommt erst in der nächsten Session

**Quellen:** DX Expert, Product Strategist

Nach `/decision-guard:init` sieht der User: ein leeres Verzeichnis, ein Template, eine CLAUDE.md-Regel. Kein sichtbares Ergebnis. Wert wird erst in einer zukünftigen Session spürbar. In Open-Source: wenn Wert nicht sofort sichtbar ist, kommen die meisten nicht zurück.

**Impact:** Hohe Drop-off-Rate nach Installation. User vergessen das Plugin bevor es Wert liefern kann.

**Fix:**
- Bei Init eine Beispiel-Decision seeden (Projekttyp aus package.json/Cargo.toml erkennen)
- Simulated Output zeigen: "In your next session, when you type 'change the color', Claude will see: [example injection]"
- Decision-Bootstrapping aus Git-History anbieten (`git log --oneline -20` analysieren lassen)

---

## WICHTIG — Sollte gefixt werden

### 6. Sicherheitsbug: Keywords werden als Regex interpretiert

**Quelle:** SRE

`prompt-check.sh` Zeile 65: `grep -qw "$kw_lower"` interpretiert Keywords als Regex-Patterns. Keyword `C++`, `node.js`, oder `[api]` verursacht Regex-Fehler oder Over-Matching.

**Fix:** `grep -Fqw` (literal string match). Ein Zeichen Änderung.

---

### 7. Status-Feld nicht quote-stripped

**Quelle:** SRE

`status: "active"` ist valides YAML, aber der Hook vergleicht `"active" != active`. Die Decision wird komplett ignoriert. Quote-Stripping existiert bereits für das Title-Feld, wurde aber nicht auf Status angewendet.

**Fix:** Gleiche Quote-Stripping-Logik wie für Title auf Status anwenden in allen 5 Hooks.

---

### 8. Zero Observability

**Quelle:** SRE

Wenn Hooks nichts tun, gibt es keinen Hinweis warum. Timeout? Parse-Fehler? Keine Matches? Der Failure-Mode ist "stille Nicht-Aktion" — genau der Zustand den das Plugin verhindern soll.

**Fix:** `DECISION_GUARD_DEBUG=1` Environment-Variable → schreibt nach `.decisions/.debug.log`. Zeigt welche Decisions gescannt, welche Keywords geprüft, und warum keine Matches gefunden wurden.

---

### 9. Fehlende Error-Recovery Skills

**Quelle:** DX Expert

Wenn Claude eine falsche Decision loggt (falscher Scope, irreführende Keywords, falsche Change Warning), muss der User die YAML-Datei manuell editieren. Kein `/decision-guard:edit` oder `/decision-guard:close`.

Außerdem: wenn `supersedes` gesetzt wird, wird die superseded Decision nicht automatisch auf den Status `superseded` gesetzt.

**Fix:**
- `/decision-guard:edit DEC-xxx` — Claude modifiziert Felder aus Konversations-Kontext
- `/decision-guard:close DEC-xxx` — Status-Übergang mit automatischer `supersedes`-Referenz-Aktualisierung
- Log-Skill: wenn `supersedes` gesetzt wird, automatisch Status der alten Decision ändern

---

### 10. Prompt Engineering Schwächen

**Quelle:** AI Architect

- **log/SKILL.md:** "Do NOT interview the user" ist eine negative Instruktion. LLMs folgen negativen Anweisungen weniger zuverlässig als positiven.
- **check/SKILL.md:** Semantisches Matching (Level 3) hat null Beispiele. Claude wendet eigenes, inkonsistentes Urteil an.
- **init/SKILL.md:** Prüft nicht ob CLAUDE.md bereits widersprüchliche Regeln enthält.
- **review/SKILL.md:** Lädt 150 Zeilen Git-Log — Token-Verschwendung für einen Staleness-Check.

**Fix:**
- Log: Positiv formulieren mit konkretem Beispiel: "Write the decision file immediately. Example: If the user said 'change to blue' and you changed 3 CSS files, write the DEC file now."
- Check: 3-4 konkrete Beispiele für semantische Matches/Non-Matches einfügen
- Init: CLAUDE.md scannen bevor appendiert wird
- Review: Git-Log auf `head -50` reduzieren

---

### 11. Positioning falsch

**Quelle:** Product Strategist

"Decision Journal" klingt nach Self-Help, nicht nach Engineering. Die "Claude's Journal" Metapher erzeugt Skepsis bei technischen Usern. Der Name `decision-guard` ist stärker als sein eigener Tagline.

**Fix:** Reframe als Safety-Tool: "Like ESLint for AI decisions." Fokus auf "verhindert dass Claude deine Arbeit rückgängig macht." Kill die Journal-Metapher im externen Marketing (intern kann sie bleiben).

---

## MINOR — Nice to fix

| # | Finding | Quelle |
|---|---------|--------|
| 12 | Scope substring-matching: Scope `api` matcht `some-api-client.js` → false positives | SRE |
| 13 | `.last_nudge` Marker wird nie zwischen Sessions bereinigt | SRE |
| 14 | `_template.md` wird von keinem Hook/Skill referenziert — toter Code | DX |
| 15 | Vergleichstabelle im README übertreibt ("No" statt "Basic/Manual" für Cursor/Memory) | AI Arch, Product |
| 16 | Kein Migrations-Pfad bei Format-Änderung in zukünftigen Versionen | SRE |
| 17 | Kein ADR-Import/Export (offensichtlichste fehlende Integration für bestehende Nutzer) | Product |
| 18 | Review-Skill lädt 150 Zeilen Git-Log in den Context | AI Arch |
| 19 | Kein `/decision-guard:status` Diagnose-Skill | DX |
| 20 | Subagents/Worktrees erhalten keine Decision-Injection (bekannte Limitation) | AI Arch |
| 21 | Anthropic baut vermutlich in 3-12 Monaten native Decision-Tracking | Product |

---

## Priorisierte Umsetzungs-Empfehlung

### Phase 1 — Quick Wins (1 Session, hoher Impact)

| Fix | Aufwand | Impact |
|-----|---------|--------|
| `grep -Fqw` statt `grep -qw` in prompt-check.sh | 1 Zeichen | Verhindert Regex-Bugs |
| Status quote-stripping in allen Hooks | 5 Zeilen pro Hook | Decisions mit `"active"` werden sichtbar |
| Universal-Conflict-Keywords ("revert", "undo", etc.) | ~20 Zeilen in prompt-check.sh | +15-20% Erkennungsrate |
| `author`-Feld aus `git user.name` in log-Skill | 3 Zeilen in SKILL.md | Team-Readiness |

### Phase 2 — Adoption-Critical (1-2 Sessions)

| Fix | Aufwand | Impact |
|-----|---------|--------|
| Tiered Injection (session-start: nur Summaries) | Rewrite session-start.sh | Skaliert bis 50+ Decisions |
| Stop-Hook: "ask" statt "block" | Rewrite stop-reminder.sh | Eliminiert False-Positive-Frust |
| Init mit Beispiel-Decision seeden | Erweitere init/SKILL.md | Sofortiger Aha-Moment |
| Debug-Modus (`DECISION_GUARD_DEBUG=1`) | ~30 Zeilen pro Hook | Diagnosierbarkeit |
| Positive Instruktionen in SKILL.md | Text-Edits | Zuverlässigeres Claude-Verhalten |

### Phase 3 — Completeness (danach)

| Fix | Aufwand | Impact |
|-----|---------|--------|
| `/decision-guard:edit` und `/decision-guard:close` Skills | 2 neue SKILL.md | Error Recovery |
| Contradiction-Detection in session-start | ~50 Zeilen | Team-Konflikte erkennen |
| Team-Workflow Dokumentation | README-Abschnitt | Adoption in Teams |
| Keyword-Index-Datei für Performance | Neues Script | Schnellere Hooks bei vielen Decisions |
| ADR-Import/Export | Neuer Skill | Integration mit bestehenden Workflows |
| Rebranding: Safety-Tool statt Journal | Copy-Änderungen | Bessere Positionierung |
