# Sublang IR: vollständige Beispiele

Diese Sammlung zeigt zwei getrennte Ebenen:

1. **Aktuelle API:** Sieben vollständige Module werden durch den vorhandenen `SublangBuilder` erzeugt und durch `SublangDump` ausgegeben. Der Quelltext liegt in [SublangExamples.ems](../../src/SublangExamples.ems). Die nummerierten `.sublang`-Dateien sind generierte Dumps dieser Module.
2. **Zielarchitektur:** [extended-ir.md](extended-ir.md) zeigt vollständige illustrative Beispiele für Profile, Ownership, Flow, GC-Integration, OO-Dispatch, dynamische Werte und High → Low → LLVM. Diese Notation ist ein Entwurf, keine bereits implementierte Syntax.

Es gibt aktuell keinen Sublang-Textparser. `.sublang`-Dateien können deshalb nicht als Compiler-Eingabe gebaut werden. Der unterstützte Einstieg ist der Builder. Die Beispiele sind in Emerald geschrieben, weil der aktuelle Builder eine Emerald-API besitzt; die erzeugten IR-Module setzen keinen Emerald-AST voraus.

## Aktuelle Module

| Dump | Inhalt | Semantisch erwartetes Ergebnis |
| --- | --- | --- |
| [01-arithmetic.sublang](01-arithmetic.sublang) | freie Funktion, direkter Call, checked i64-Addition | `main()` → 42 |
| [02-branch.sublang](02-branch.sublang) | if/else, Merge mit Blockparameter | `max(20,42)` → 42 |
| [03-loop.sublang](03-loop.sublang) | Loop mit zwei SSA-Blockparametern | `sumBelow(10)` → 45; `sumBelow(0)` → 0 |
| [04-record.sublang](04-record.sublang) | Record konstruieren, lesen, neue Version erzeugen | `main()` → 43; ursprüngliches `Pair.x` bleibt 20 |
| [05-object.sublang](05-object.sublang) | Klasse, Initialisierung, Mutation, borrowed Receiver, Scope | `main()` → 42 |
| [06-float.sublang](06-float.sublang) | f64 add/sub/mul/div mit explizitem Rundungsmodus | `calculate(6.0,2.0)` → 6.0 |
| [07-failure.sublang](07-failure.sublang) | expliziter Failure-Terminator | `requireNonNegative(42)` → 42; negative Eingabe → Failure |

Die Ergebnisse beschreiben die Bedeutung der IR; der Beispielgenerator interpretiert oder kompiliert die erzeugten Module nicht. Er baut die Datenstrukturen, prüft ihre strukturelle Gültigkeit und schreibt Dumps. `main()` mit einem i64-Ergebnis ist hier eine IR-Funktion, keine bereits festgelegte native Prozess-Entry-ABI.

## Dump lesen

```text
v3:Int = int.add v1@value, v2@value overflow=trap failure=example.integer_failure span=1
```

- `v3` ist eine SSA-Value-ID innerhalb einer Funktion; Definition genau einmal.
- `Int` ist im jetzigen Schema signed i64, `Float` ist f64.
- `@value`, `@borrow_read`, `@borrow_write` und `@init` sind Operand-/Parameter-Modi.
- `overflow=trap` fordert einen Fehlerpfad an. Im jetzigen Schema bezeichnet `failure` noch einen Namen; ein vollständiger FailureAction-Vertrag gehört zu A.1.
- `span=1` verweist auf einen Herkunftseintrag. Die Beispiele verwenden synthetische Herkunft, Produktionsfrontends liefern echte Source-Spans.
- IDs beginnen in jeder Funktion bzw. Tabelle neu; identische Value-IDs in verschiedenen Funktionen bezeichnen verschiedene Werte.

### Schleifen und Sprünge

`branch` übergibt alle Operanden als Argumente an die Zielblockparameter. Bei `cond_branch` steht zuerst die Bool-Bedingung; danach kommen die Argumente für den true-Zweig, dann für den false-Zweig. `trueArgs=N` gibt die Zahl der true-Argumente an, ohne die Bedingung.

```text
cond_branch v6@value, v5@value targets=[3,4] trueArgs=0 span=1
```

Das heißt: Ist `v6` wahr, gehe ohne Argumente nach Block 3; andernfalls übergib `v5` an Block 4. Ein Loop-Backedge übergibt neue Werte an die Header-Blockparameter. Es gibt keine implizit veränderlichen SSA-Variablen.

### Records versus Klassen

`record.with` liefert einen neuen Wert; das ursprüngliche Record wird nicht mutiert. Ein Record benötigt auf IR-Ebene keine Referenzidentität und keinen eigenen Heap-Header. Das konkrete ABI-/Containerlayout wird später geplant.

`class.new` erzeugt eine Referenz auf ein logisches Objekt. `field.init` initialisiert, `field.write` verändert ein mutables Feld. `methodOf` und der explizite Receiver modellieren eine Methode; im aktuellen Beispiel ist der Call direkt. Vererbung und virtueller Dispatch sind erst im erweiterten Entwurf dargestellt.

`scope.end` beweist derzeit weder korrekte Lebensdauer noch tatsächliche Freigabe: Der vorhandene Verifier prüft Struktur, Typen und Dominanz. `lifetime=not_checked` und `codegenReady=false` bleiben deshalb auch bei gültigen Modulen bestehen. `noescape` ist eine deklarierte Information und kein hier bereits ausgeführter interprozeduraler Beweis.

## Ein gebündelter Sandbox-Lauf

Vom Projektroot:

```bash
bash scripts/sublang-examples-sandbox.sh
```

Der Runner entspricht der bestehenden Harness-Sandbox: 6.000.000.000 Bytes RAM, identisches Memory+Swap-Limit (kein Swap), kein Netzwerk, read-only Projekt und temporäre Build-Dateien. Er baut den Generator einmal und prüft alle sieben Module in einem Lauf. Er startet keinen vollständigen Selfhost-Bootstrap und keine Benchmark-Suite.

Die Dumps werden als lesbare Beispiele eingecheckt; nach Änderungen an Builder/Schema müssen sie aus dem Generator neu erzeugt werden. Sie sind keine zusätzlichen Golden-Tests. Der Ausführungsstatus dieser Fassung steht in [verification.txt](verification.txt).

## Ergänzungen v0.4

[Sublang IR Contracts](../../docs/Sublang_IR_Contracts.md) macht Effekte mit Herkunft, Alias-Abstraktion, getrennte Pass-Prüfungen, Exception-CFG und öffentliche Protokollgrenzen verbindlich. Dynamische Sprachen erhalten einen realen eigenen AOT-Integrationsschritt. Die [erweiterten Beispiele](extended-ir.md) zeigen zusätzlich einen konkreten Escape-Blocker mit Explain-Bericht, Invoke/Cleanup/Resume und einen Pass-/Capability-Protokollbericht. Diese Ergänzungen ändern weder die sieben erzeugten schema=1-Dumps noch deren ursprünglichen Prüfstatus.

## Vollständig auf v0.4 überarbeitete Zielmodule

Die neuen Verträge wurden jetzt in die bestehenden Zielbeispiele eingearbeitet, statt nur zusätzliche Anmerkungen anzuhängen. Unter [v0.4/](v0.4/readme.md) liegen elf einzelne High-/Low-Modulbeispiele mit gemeinsamen Effektsummaries, Provenance und passenden Runtime-/Lifetime-Verträgen. Dynamische Strings bleiben über allokierende Calls GC-sichtbar; der Exception-Fall zeigt Cleanup, Catch und Wiederwurf; ein Ownership-Transfer demonstriert ausdrücklich ein Objekt, das seinen lexikalischen Scope überlebt.

[extended-ir.md](extended-ir.md) enthält dazu zusammengehörige Pläne, Alias-/Explain-, Pass- und Protokollberichte sowie die Abdeckung aller Nutzeranforderungen. Positive Analyse-/Prüfresultate sind dort erwartete Entwurfsberichte. Die früher generierten `.sublang`-Dumps bleiben unverändert, da der aktuelle Builder die neuen Verträge noch nicht implementiert.
