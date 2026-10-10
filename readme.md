# Sublang

Sublang ist eine sprachunabhängige Compilerplattform, derzeit in **Emerald (`.ems`)** implementiert. Dieses Repository enthält ihren neutralen IR-Kern, die zugehörigen Beispiele und Architekturverträge. Es ist vom Emerald-Compilerprojekt getrennt.

- **Optimind** bezeichnet die allgemeine Analyse-, Optimierungs- und Passengine der Plattform. Ihre vollständige Pipeline ist noch im Aufbau; der vorhandene strukturelle IR-Verifier ist kein bereits fertiger Optimizer.
- **HyperAlloc Flow** ist das optionale Paket für Objekt-/Speicheroptimierung mit Managed- und Integration-Modus. Sublang ohne dieses Paket bleibt ein vorgesehenes korrektes Einsatzmodell.
- **LLVM** bleibt das finale Backend. Quellsprachen behalten ihre eigenen Semantik- und Runtime-Verträge.
- Eine fusionierte Sprache und eine neue Source-Endung sind nicht Bestandteil dieses Repositories. Die Implementierung bleibt Emerald.

Repository: https://github.com/emvus/sub-lang

## Aufbau und lokaler Einstieg

```text
src/sublang/       neutrale IR, Builder, Dump, struktureller Verifier und Options
src/SublangHarness.ems
src/SublangExamples.ems
examples/ir/       Builder-Dumps und ausdrücklich getrennte Zielsyntax
scripts/          isolierte Build-/Check-Einstiege
docs/             technische Verträge, Overview und Migration
```

Emerald ist eine externe Toolchain-Abhängigkeit. Keine Compiler-Binaries oder Emerald-Frontendquellen werden hier dupliziert. Für den lokalen Checkout wird der benachbarte Ordner `../Emerald LLVM` verwendet; andernorts den Pfad explizit setzen:

```bash
SUBLANG_EMERALD_ROOT="/path/to/Emerald LLVM" bash scripts/check-sandbox.sh all
```

Der Runner baut Harness und Beispielgenerator in einem Netzwerk-isolierten Container mit 6 GB RAM und ohne Swap. Er mountet beide Repositories read-only. Er führt keinen großen Selfhost-Bootstrap durch. Die Scripts dürfen keinen Compiler außerhalb dieser Sandbox starten.

Öffentliche Prozess-CLI, Wire-IR, Low-IR/LLVM-Pipeline und die vollständige Optimind-/HyperAlloc-Integration sind Zielverträge, noch keine veröffentlichten APIs. `sublang::*` und `Sublang*` sind die aktuellen internen Emerald-Packages/Klassen; `Sublang-*` sind Diagnosecodes. Lesbare `.sublang`-Dumps und `.sublang-ir`-Entwürfe sind keine Sprachdateien oder ein festes binäres Eingabeformat.


**Sublang soll eine wiederverwendbare Compiler- und Optimierungsbasis für unterschiedliche Programmiersprachen werden.** Eine Sprache liefert typisierte Zwischendarstellung und explizite Semantik-Verträge. Sublang übernimmt passende Analysen, Optimierungen und die Absenkung zu LLVM. Optional kann Flow auch die Speicherverwaltung und interne Objektrepräsentation übernehmen.

Emerald ist das erste Frontend und die technische Ausgangsbasis. Der neutrale Sublang-Kern soll weder Emerald-Syntax noch dessen Klassenmodell, Standardbibliothek oder Runtime voraussetzen.

> **Entwicklungsstand, 10. Oktober 2026:** Die Architektur ist in Arbeit. Der erste IR-, Builder-, Dump- und strukturelle Verifier-Baustein liegt unter `src/sublang/`; Auftrag A ist umgesetzt und wartet auf Architektur-Review. Diese README beschreibt überwiegend die Zielarchitektur, keine bereits vollständig verfügbare Funktionsliste. Der Lifetime-/Effektnachweis, die Sublang-LLVM-Pipeline und die unten beschriebenen Flow-Runtime-Modi sind noch nicht vollständig implementiert oder abgenommen. Der bestehende Emerald-Compiler bleibt der funktionierende Ausgangspfad.

## Warum Sublang für andere Sprachen interessant ist

Ein Sprachentwickler soll eigene Syntax, Typregeln und Semantik behalten können, ohne sämtliche Optimierungen, Objekt-Lowerings und Speicheranalysen selbst neu entwickeln zu müssen.

Sublang ist für zwei Integrationswege gedacht:

- **Optimierungsbibliothek:** Ein vorhandener Compiler erzeugt Sublang IR, führt ausgewählte Pässe aus und übernimmt die Ergebnisse beziehungsweise die abgesenkte IR wieder. Die LLVM-Anbindung kann beim vorhandenen Compiler bleiben. Ein vorhandener C-Backend-Pfad darf neben Sublang/LLVM weiterbestehen; Sublang optimiert dadurch nicht automatisch beliebigen erzeugten C-Text.
- **Compiler-Framework:** Ein Sprach-Frontend nutzt zusätzlich Sublang für Speicherplanung, Runtime-Anbindung, LLVM-Ausgabe und Build.

Eine Sprache muss dafür nicht wie Emerald aussehen. Prozedurale Funktionen, funktionale Werte und objektorientierte Klassen sind unterschiedliche Fähigkeiten derselben Architektur. Eine Sprache mit eigenem GC muss diesen nicht austauschen, um kompatible Sublang-Optimierungen zu nutzen.

Der Integrationsaufwand bleibt real: Ein Frontend muss Typen, Aufrufziele, Auswertungsreihenfolge und Sprachregeln korrekt übersetzen. Eine Konfigurationsdatei allein beschreibt keine beliebige Sprache.

## Der Weg bis LLVM

```text
Emerald-Frontend ───────────┐
Prozedurales Frontend ──────┼─→ Sublang High IR + Semantik-Verträge
Weiteres Sprach-Frontend ──┘                  │
                                   Prüfung und Analysen
                                             │
                                  optionale Optimierungspässe
                                             │
                                  Speicher- und Layoutplanung
                                             │
                                         Sublang Low IR
                                             │
                                           LLVM IR
                                             │
                                      Maschinencode
```

**High IR** bewahrt Zusammenhänge wie Werte, Objektidentität, Methoden, Ownership und Lebensdauer. **Low IR** beschreibt die gewählte Repräsentation, konkrete Speicheroperationen, Aufrufe und Cleanup. LLVM übernimmt die anschließende maschinennahe Optimierung und Codegenerierung.

So kann Sublang eine Optimierung begründen, bevor die dafür wichtigen Sprachinformationen in rohe Pointer und Speicherzugriffe aufgelöst wurden.

## Core IR und Erweiterungen

Sublang soll eine kleine Basis mit optionalen, versionierten Erweiterungen erhalten. Keine zwei voneinander abweichenden „normalen“ und „extended“ Compilerpipelines: Erweiterungen werden im gemeinsamen IR-Modell kombiniert.

| Bereich | Ausdrucksmöglichkeiten |
| --- | --- |
| **Core** | Primitive Typen, Wertaggregate, freie Funktionen, typisierte SSA-Werte, Kontrollfluss, direkte Aufrufe und explizite Rechenregeln |
| **Object** | Referenzklassen, Identität, Felder, Methoden sowie später Interfaces, Vererbung und dynamischer Dispatch |
| **Memory** | Ownership, Borrowing, Referenzbeziehungen, Lebensdauer, Transfers und Speicheranforderungen |
| **GC/Runtime** | Collector-Integration, Roots, Barriers, Safepoints, Pinning, Weak References und Finalizer-Verträge |

Funktionswerte und Closures sind eine spätere Erweiterung; Captures werden explizit modelliert. Eine Quellklasse ist dafür nicht vorgeschrieben.

**High/Low und Core/Extensions sind unterschiedliche Achsen:** High/Low bezeichnet die Absenkungsstufe, Extensions die verwendeten Fähigkeiten. Ein prozedurales Programm kann ohne Object-Erweiterung arbeiten. Eine GC-basierte objektorientierte Sprache kann Object und GC/Runtime kombinieren.

Korrektheitsrelevante Erweiterungen sind keine ignorierbaren Kommentare. Ein Pass muss sie verstehen, nachweislich erhalten oder ihre Bearbeitung auslassen. Eine unbekannte notwendige Erweiterung wird vor Codegenerierung diagnostiziert. Extension-Operationen brauchen Typregeln, Effekte, Verifikation und ein passendes Lowering.

## Flow: gemeinsame Analyse, unterschiedliche Speicheranbindung

HyperAlloc Flow soll als optionales Sublang-Paket auf neutraler Sublang IR arbeiten. Es soll nicht mehr den Emerald-AST benötigen. Objektgraphen, Mutation, mögliche Escapes, Ownership und Laufzeiteigenschaften werden aus der IR und ihren Verträgen analysiert.

Die Analysebasis ist gemeinsam; Speicherplanung und Runtime-Anbindung unterscheiden sich.

### Flow Managed Mode

Die Sprache entscheidet sich ausdrücklich dafür, Flow die Speicherverwaltung zu übergeben. Flow wählt anhand bewiesener Eigenschaften und Runtime-Fähigkeiten geeignete Strategien:

- Werte direkt in Aggregaten oder Collections speichern.
- Nicht entweichende Objekte auf dem Stack platzieren.
- Geeignete Lebensdauern über Regionen oder wiederverwendbare Speicherbereiche verwalten.
- Eindeutig besessene Objekte deterministisch freigeben.
- Geteilte beziehungsweise zyklische Graphen mit kompatiblen Runtime-Mechanismen verwalten.

**Auto ist hier die Strategieauswahl innerhalb des gewählten Modus.** Sie ist keine Erlaubnis, den bisherigen GC ungefragt auszutauschen. Auch vollständig von Flow verwaltete Programme benötigen für nicht statisch entscheidbare Fälle passende Runtime-Mechanismen.

Der bestehende Bond-Mechanismus mit Cycle Collection ist eine Implementierungsbasis, kein vollständiger Ersatz für jeden Tracing GC. Weak References, Finalizer, Resurrection, bewegliche Objekte, Reflection und Nebenläufigkeit benötigen zusätzliche präzise Verträge und gegebenenfalls neue Runtime-Funktionen. Managed Mode ist nur für tatsächlich unterstützte Semantik zulässig und bedeutet nicht automatisch „ohne GC“.

### Flow Integration Mode

Die Sprache behält ihren GC beziehungsweise ihr Speichersystem. Flow liefert kompatible Analysen und Optimierungen und arbeitet über einen Provider mit diesem System zusammen.

Der Provider beschreibt unter anderem Roots, Write Barriers, Safepoints, bewegliche Referenzen, Pinning und Aufrufe in nativen Code. Eine Stack- oder Layout-Optimierung darf nur stattfinden, wenn sowohl die Sprachsemantik als auch der Collector-Vertrag das erlauben.

Integration Mode ist mehr als das Linken gegen eine GC-Bibliothek: Der Compiler muss die erforderlichen Operationen an den richtigen Stellen erhalten beziehungsweise erzeugen.

### Geplante Konfiguration

Die folgende Schreibweise ist ein Architekturvertrag, noch keine Anleitung für bereits verfügbare CLI-Schalter:

| Geplante Option | Bedeutung |
| --- | --- |
| `--sublang-flow=off` | Optionales Flow-Passpaket deaktivieren; notwendige Sprachprüfung und Speicherverwaltung bleiben aktiv. |
| `--sublang-flow=on` | Flow ausdrücklich anfordern; fehlende Implementierung oder notwendige Fähigkeiten diagnostizieren. |
| `--sublang-flow=auto` | Flow nach Frontend-Empfehlung und Fähigkeiten auswählen; effektiven Modus ausweisen. |
| `--sublang-memory=language` | Den von der Sprache gewählten Speicher-Provider beibehalten; dies ist der Default. |
| `--sublang-memory=hyperalloc-managed` | Flow ausdrücklich als Speicherverwaltung wählen. |
| `--sublang-memory=hyperalloc-integration` | Flow ausdrücklich mit dem vorhandenen GC-/Speicher-Provider integrieren. |

Explizite Flow-Speichermodi benötigen ein aktives Flow-Paket. Zusammen mit `--sublang-flow=off` sind sie widersprüchlich und werden abgelehnt. Bei `auto` fordert die explizite Auswahl eines Flow-Speichermodus Flow an. Ein erforderlicher, aber fehlender Provider darf nicht still ersetzt werden.

## Sprachregeln bleiben verbindlich

Sublang muss wissen, welche Transformationen eine Sprache erlaubt. Dazu gehören:

- Integer-Breite und Overflow: prüfen, umbrechen oder eine andere ausdrücklich unterstützte Semantik.
- Float-Regeln, NaN-Verhalten, Rundung und erlaubte Reassoziation.
- Wertkopien gegenüber Referenzen, Mutation und beobachtbare Objektidentität.
- Aufrufeffekte, mögliche Escapes, Besitztransfer und Herkunft geliehener Ergebnisse.
- Exceptions, Finalizer, Nebenläufigkeit, Reflection und native Schnittstellen.

Unbekannt ist keine Garantie. Sublang darf eine Optimierung auslassen, benötigt für erfolgreiche Codegenerierung aber weiterhin eine korrekte Grundimplementierung. Eine nicht unterstützte notwendige Sprachregel führt zur Diagnose.

Insbesondere darf das Abschalten von Flow weder Emeralds Ownership-Regeln noch Überlaufprüfungen oder erforderliche Freigaben abschalten. Ein Heap-Fallback allein löst keine Lifetime-Probleme.

## Physische Objektrepräsentation

Sublang soll interne Speicherlayouts optimieren können: beispielsweise kleine geeignete Objekte ohne eigenen Header direkt in einer Liste speichern. Dabei bleibt die ursprüngliche Sprachsemantik maßgeblich.

Veränderliche Identität, extern sichtbare Layouts, FFI, Reflection, Serialisierung und Finalizer können Änderungen verhindern oder Adapter erforderlich machen. Ziel-Layout und Alignment kommen aus der LLVM-Target-Konfiguration; Runtime-Header und Collector-Metadaten vom jeweiligen Provider. Emeralds vorhandener 16-Byte-Header wird damit kein Pflichtlayout für andere Sprachen.

## Welche Optimierungen Sublang übernehmen soll

Die Ausgangsbasis ist vorhandener Emerald-Code, der schrittweise entkoppelt wird:

- Escape-/Lifetime-Analyse, skalare Ersetzung und Value-Class-Inferenz.
- Geeignete Stack-, Pool- und Region-Allokationen sowie Ownership-/Sharing-Strategien.
- Konstante String-Literale und kompatible Collection-Repräsentationen.
- Direkte Aufrufe statt dynamischem Dispatch, sofern das Aufrufziel bewiesen ist.
- Effekterhaltende Optimierung vor der LLVM-Absenkung.
- LLVM-Optimierung sowie LTO-/PGO-Build-Anbindung.

Nicht jeder Pass ist Flow, und nicht jeder Pass passt zu jeder Sprache. String-/Collection-Pässe benötigen definierte Bibliotheksverträge; ein Name wie „List“ genügt nicht. LLVM/LTO/PGO bleiben von der Flow-Aktivierung getrennt.

## Integration einer anderen Sprache

1. Syntax, Typen und Namen im eigenen Frontend auflösen.
2. Passende Core-/Extension-Operationen mit konkreten Typen und SourceSpans erzeugen.
3. Sprachsemantik und überprüfbare beziehungsweise vertrauenswürdig deklarierte Effektverträge liefern.
4. Vorhandene Runtime-/GC-Funktionen mit vollständiger ABI und ihren Fähigkeiten anbinden oder einen kompatiblen Flow-Provider wählen.
5. IR prüfen, geeignete Pässe wählen und den Speicherplan bilden.
6. Über Sublang oder den eigenen Backend-Adapter nach LLVM absenken.

Dynamisch typisierte Sprachen sind ein verbindliches Integrationsziel: Dynamische Werte, Typprüfungen, Aufrufe und Runtime-Fallbacks erhalten explizite IR-Verträge und einen eigenen kleinen AOT-Integrationspfad. JIT, Deoptimierung und vollständige Reflection-Unterstützung sind keine bereits zugesagten Eigenschaften des ersten Sublang-Kerns.

## Schrittweise Entwicklung

1. **IR-Kern und Verträge:** Builder, struktureller Verifier und deterministischer Dump. Erste Bausteine sind vorhanden; vor LLVM werden Semantikprofile, ABI-/Failure-Verträge, Owned-Ergebnisse und bitgenaue Konstanten vervollständigt. Strukturelle Gültigkeit ist noch kein Lifetime-Nachweis.
2. **Erste Strecke bis LLVM:** Freie Funktion, Werttyp und einfache Referenzklasse über einen begrenzten Emerald-Adapter. Der bisherige Compilerpfad bleibt erhalten.
3. **Erweiterungen und zweites Frontend:** Object-/Memory-Verträge ausbauen und mit einer kleinen nicht objektorientierten Sprache die Unabhängigkeit prüfen.
4. **Flow-Paket und Provider:** Bestehende Analysen migrieren; Integration und Managed Mode in belegbar unterstützten Schritten entwickeln.
5. **Emerald-Selfhost über Sublang:** Feature-Abdeckung erweitern und erst nach Verifikation den neuen Pfad produktiv machen.

Compiler-/Selfhost-Läufe bleiben sandboxed mit maximal 8 GB RAM; bevorzugt 6 GB ohne Swap. Prüfungen werden auf aussagekräftige Fälle je neuer Grenze begrenzt

## Technische Zielvorgabe und berichtete Evidenz

Die vom Nutzer bereitgestellte [Sublang Technical Overview](docs/Sublang_Technical_Overview.md) ist als redaktionell migrierte Fassung im Projekt archiviert. Die technischen Anforderungen und Umsetzungsetappen stehen in [Sublang IR Contracts](docs/Sublang_IR_Contracts.md). Vor der LLVM-Anbindung werden Semantikprofile, ABI-/Failure-Verträge, Ownership-Ergebnisse und bitgenaue Float-Konstanten vervollständigt.

Das Overview enthält berichtete Emerald-Messungen und dokumentierte Nichtabschlüsse bei regex-redux und k-nucleotide. Diese Angaben wurden in diesem Dokumentationsschritt nicht unabhängig nachgemessen. Sie sind Evidenz für die jeweils berichteten Emerald-Stände, keine Benchmarks des unabhängigen Sublang-Kerns, keine universelle Sprachrangliste und keine garantierten Geschwindigkeitsziele für neue Frontends. Die Sublang-Integration und jeder Provider brauchen eine eigene passende Verifikation. Noch nicht verfügbare Funktionen werden nicht durch solche Zahlen als produktionsreif ausgewiesen.

## Sublang-IR-Beispiele

[Sublang-IR-Beispiele](examples/ir/readme.md) zeigen sieben vollständige, strukturell geprüfte Builder-Module mit echten Dumps. Ergänzende Entwurfsbeispiele beschreiben die erweiterte IR, Flow-Modi, GC-Integration und High → Low → LLVM; ihr Implementierungsstatus ist getrennt ausgewiesen.

## Effektverträge, öffentliche Schnittstelle und Dynamic

[Sublang IR Contracts v0.4](docs/Sublang_IR_Contracts.md) konkretisiert erstklassige Effekte mit deklarierter, konservativer oder bewiesener Herkunft; gemeinsame Alias-/Location-Bezüge; getrennte Struktur-, Semantik- und Memory-/Lifetime-Prüfungen; sowie explizite Exception-/Cleanup-Kontrollflüsse. Explain soll konkrete Calls oder Alias-Beziehungen benennen, die eine Optimierung blockieren. Ein lexikalisches scope.end beweist keine Objektlebensdauer.

Für die Auslieferung als Binary ist ein versioniertes Prozessprotokoll mit Schema-/Feature-Negotiation geplant. Die bisherigen .sublang-Dumps sind kein öffentliches Eingabeformat oder stabile ABI. Native Bibliotheks-ABI und Wire-IR werden separat von internen Datenmodellen versioniert.

Nach der begrenzten statischen LLVM-Strecke folgt verbindlich ein kleiner AOT-Pfad für eine dynamische Minisprachsemantik einschließlich heapfähiger Werte und Runtime-Calls. JIT, vollständiges JavaScript/Python und universelle GC-Abdeckung sind damit nicht implementiert oder automatisch zugesagt. Diese Punkte sind Zielverträge, keine Fertigstellungsmeldung.
