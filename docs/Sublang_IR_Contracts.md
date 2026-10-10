# Sublang IR Contracts — Zielvertrag v0.4

Status: verbindliche Architekturvorgabe, noch kein implementiertes öffentliches Schema oder ABI. Ergänzt `Sublang_Technical_Overview.md` und die bisherigen Verträge. Die derzeitige schema=1-IR ist ein begrenztes Builder-Modell; `.sublang` bleibt ein Dump. Implementierung und tatsächliche Abnahme werden getrennt gemeldet.

Dynamisch typisierte Sprachen sind jetzt ein verpflichtender Integrationsfall. Sie erhalten dieselben Core-, Effekt-, Alias-, Speicher- und Verifikationsverträge wie statische Sprachen, ergänzt durch explizite Dynamic-Operationen. LLVM bleibt das finale Backend. Ein JIT ist dafür nicht erforderlich.

## 1. Effekte als erstklassige Eigenschaften

Funktionen, Call-Sites und effektbehaftete Operationen referenzieren typisierte, versionierte EffectSummary-Datensätze. Der Operand-Modus `borrow_read` beschreibt Zugriff auf einen Wert und ersetzt keinen Effektvertrag.

Ein Summary modelliert mindestens:

| Bereich | Bedeutung |
| --- | --- |
| allocation | mayAllocate, einschließlich potentieller GC-Safepoints |
| escape | mayEscape pro Argument, Resultat, Capture und global erreichbarem Ziel |
| failure | mayFail und konkrete FailureActions; abort bleibt beobachtbar |
| exceptions | mayThrow, zulässige Exception-Mengen oder unknown, Unwind-Vertrag |
| memory | Reads/Writes als Location-/Region-Mengen, einschließlich globals, runtime und unknown |
| synchronization | Atomics, Locks, Fences, Thread-/Task-Effekte und MemoryOrder oder unknown |
| observable | I/O, volatile Zugriffe, Finalizer-/Runtime-Effekte oder unknown |
| control | mayDiverge, returnsNormally, noreturn nur mit gültigem Nachweis |

Jedes Feld kann unknown ausdrücken. Ein fehlendes Feld bedeutet niemals „nein“. read/write=unknown aliasiert potentiell jede kompatible erreichbare Location. Allocation ist kein Synonym für Escape; Synchronisation ist kein gewöhnlicher Field-Write. Eine reine Signatur belegt weder Terminierung noch freie Verschiebbarkeit eines Calls.

### Herkunft und Vertrauen

- **Declared:** Frontend-/Provider-Vertrag, mit Herkunft und Vertrauensstatus. Ein ungeprüfter Hinweis ist keine Optimierungsgarantie. Ein explizit vertrauter externer ABI-Vertrag kann eine Garantie sein; dessen Lieferant trägt die semantische Verantwortung.
- **AssumedConservative:** Sounde Obergrenze bei fehlenden Fakten, typischerweise unknown/top. Keine spekulative Annahme „wird schon nicht allokieren“. Optimistische Annahmen benötigen einen unterstützten Guard/Fallback; dieser gehört nicht zum ersten AOT-Umfang.
- **Proven:** Analyseergebnis mit Pass-/Analyse-ID, EntityKey, Modulrevision, Voraussetzungen und Abhängigkeiten.

Die Herkunft wird pro Fakt gespeichert, weil ein Summary beispielsweise bewiesene Reads und unbekanntes Escape kombinieren kann. Deklaration und Beweis dürfen voneinander abweichen; dann wird eine widersprüchliche Definition diagnostiziert, nicht die günstigere Angabe ausgewählt. Das wirksame Summary referenziert seine Fakten und ist eine sichere Obergrenze aller möglichen Ziele und Effekte.

Interprozedurale Analyse vereinigt die Effekte aller möglichen Dispatch-Ziele. Rekursive Callgraph-Komponenten benötigen einen Fixpunkt. Bei offenen Zielmengen bleiben konservative Rest-Effekte. noescape allein erlaubt weder noalias, readonly, nounwind, nosync noch memory(none). LLVM-Attribute entstehen erst aus dafür hinreichenden wirksamen Verträgen.

## 2. Gemeinsame Alias-Abstraktion

LocationId beschreibt logischen Speicher: globale Variable, Allokationsstelle/Objekt, Feldpfad, Container-Speicher, Argumentregion, Runtime oder UnknownLocation. Logische Locations sind unabhängig von physischen Offsets des späteren MemoryPlan. Physische Pointer-Provenienz kommt beim Lowering hinzu.

AliasQuery liefert NoAlias, MayAlias oder MustAlias, jeweils mit Herkunft, Revision und Voraussetzungen. Fehlende Information liefert MayAlias. Ein Argumentpaar ist nicht allein aufgrund verschiedener SSA-IDs oder borrow_read disjunkt. Field-Sensitivity benötigt einen passenden Layout-/Objektvertrag; unsichere Pointer, FFI und Reflection können Fakten vergröbern.

Reads/Writes, Escape-Kanten, Borrow-Ursprung, invalidierende Container-Operationen und GC-Bewegung verwenden dieselben Location-Bezüge. Eine sichere Borrow-Ansicht braucht Owner-, Bereichs- und Invalidierungsabhängigkeiten, nicht nur einen Scope-Namen. Effekte bilden Abhängigkeiten für Call-/Load-/Store-Verschiebungen; mutierende Pässe müssen diese Beziehungen erhalten oder die zuständige Analyse neu ausführen. Ein MemorySSA- oder Token-Modell kann die Umsetzung liefern; seine genaue Repräsentation ist kein bereits verfügbares API-Versprechen.

## 3. Lexikalische Scopes, Lifetime und Ownership

`scope.begin/end` beschreibt eine lexikalische Grenze oder einen Kandidaten für Cleanup. Daraus folgen weder automatisch Objektfreigabe noch Nicht-Escape oder vollständige Initialisierung.

Gesonderte Analysen prüfen Initialisierung, Ownership-Zustände, Transfers, Borrows und Invalidierung, tatsächliche Referenz-Liveness, Escapes und Cleanup-Pfade. Objekt-, Borrow-, Stack- und Region-Lebensdauern werden getrennt modelliert. SSA-Liveness allein ist kein Beweis für unerreichbare Objektgraphen.

Ein MemoryPlan darf erst nach diesen Prüfungen Stack-Lifetime, Drop, Pool-Reuse, Regionsfreigabe oder GC-Roots konkretisieren. Ein Borrow auf ein Container-Element kann durch Reallocation/Mutation invalidiert werden, obwohl der lexikalische Scope weiterbesteht. Umgekehrt kann ein entkommenes owned Objekt seinen Ursprungsscope überleben, wenn ein gültiger Transfer/Provider-Vertrag besteht.

## 4. Fehler, Exceptions und vollständiger CFG

FailureAction beschreibt Verhalten, Payload, Runtime-Bindung, ABI und Kontrollfluss. Anfangs unterstütztes abort und späteres throw sind verschiedene Verhaltensweisen; throw darf niemals still als abort abgesenkt werden.

- Abort/Trap: expliziter nicht zurückkehrender Fehlerpfad. Ob Cleanup vor Prozessende beobachtbar erforderlich ist, legt das Profil fest.
- Throw: Exception-Payload plus explizite Unwind-Kante. Throwing Calls werden als `invoke` mit normalem und exceptional Nachfolger modelliert; der normale Ergebniswert ist nur auf der normalen Kante definiert.
- Throwing checked-Arithmetik: explizite Fehlerkante oder checked-invoke-Form. Kein unsichtbares Unwinding hinter einem gewöhnlichen `int.add` ohne CFG-Vertrag.
- Catch: typisierte Exception-Filter, Bindung und ggf. Wiederwurf. Ein blockübergreifender Exception-Token trägt Herkunft/Runtime-Vertrag und nötige GC-Sichtbarkeit.
- Cleanup/finally: auf allen vorgeschriebenen normalen und exceptional Ausgängen genau die erforderlichen Aktionen. Reihenfolge, erneute Exceptions und Suppression bestimmt das Sprachprofil.
- Resume: unwinding fortsetzen; kein gewöhnlicher Return. Relevante borrowed/owned Werte bleiben bis zu ihrem korrekten Cleanup gültig.

Unwind-ABI, Personality und LLVM-EH-Modell sind Target-/Runtime-Verträge. Die Low IR konkretisiert landingpad/resume oder funclet-basierte Umsetzung. Profile mit Exceptions bleiben bis zur tatsächlichen Unterstützung explizit unsupported; der erste abort-only Pfad bleibt zulässig und begrenzt.

## 5. Pass-Verträge und Validierung

Jeder Pass deklariert benötigte Extensions/Versionen, Eingangsstufe, Vorbedingungen, Analysen, semantische Veränderungen (normalerweise keine), Ausgangsstufe und invalidierte/erhaltene Ergebnisse.

Getrennte Prüfdimensionen:

1. **Struktur:** IDs, Typreferenzen, SSA/Dominanz, Terminatoren, normaler und exceptional CFG, Kantenargumente.
2. **Semantik:** Profil-/Operation-Kompatibilität, Integer-/FP-Regeln, Effektverträge, Failure-/Exception-Verhalten, Extension-/ABI-Verträge.
3. **Memory/Lifetime:** Initialisierung, Ownership, Aliasing/Borrows, Cleanup, Roots/Barriers/Safepoints, Layout-/Provider-Gültigkeit.

Status pro Dimension: valid, invalid, not_checked oder not_applicable mit begründeter Feature-Abdeckung. Kein implizites „valid“ bei ausgelassenem Prüfer. codegenReady ist nur wahr, wenn alle für akzeptierte Features und Ziel/Provider notwendigen Prüfungen gültig sind.

Jeder Pass erzeugt einen neuen Snapshot beziehungsweise eine kontrolliert versionierte Mutation; Analysen beziehen sich auf genau diesen Stand. Nach jedem Transformationspass muss der Passmanager gültige Ausgangs-IR sicherstellen: strukturelle Prüfung, Überprüfung passrelevanter semantischer/Memory-Invarianten und nachvollziehbare Erhaltung unveränderter gültiger Ergebnisse. Wo kein sounder Erhaltungs-/Inkrementalvertrag besteht, wird neu geprüft. Vor sicherheitskritischem Lowering und Codegen erfolgt die vollständige für den gewählten Umfang notwendige Prüfung. Keine vollständige Testsuite pro Passlauf nötig.

Pass-Validierung beweist nicht automatisch Äquivalenz beliebiger Programme. Transformationskorrektheit braucht einen passenden Passvertrag und Implementierungsevidenz; ein Verifier allein erkennt nicht jede falsche Konstantenfaltung. Erforderliche zusätzliche Regressionen bleiben klein und zielgerichtet.

## 6. Explain und Debug als gemeinsame Schnittstelle

Diagnosen und Optimierungsentscheidungen sind strukturierte Datensätze, keine ausschließlich frei formulierten Logs. DecisionId/DiagnosticCode, Severity, EntityKey, SourceSpan, Pass/Analyse, Revision, angeforderte/effektive Strategie, Provider sowie Beweis-/Blocker-Bezüge sind maschinenlesbar.

Beispiel: `FLOW-LOCAL-ESCAPE-UNKNOWN` für `%point`, blockiert durch Call `@plugin.apply`, dessen effektives Escape-Summary argument0=unknown aus konservativer Herkunft trägt. Ein Alias-Blocker nennt beide Locations, die MayAlias-Kante und deren Ursprung. Die Erklärung nennt die gewählte korrekte Alternative; sie suggeriert keine automatische Kopie oder sichere noescape-Annotation.

Explain unterscheidet „Optimierung ausgelassen“ von „benötigte Sprachsemantik nicht unterstützt“. Textansicht und binäre Antwort verwenden dieselben Datensätze. Normalbetrieb sammelt nur kompakte Entscheidungen; ausführliche Beweisgraphen und IR-vorher/nachher-Snapshots sind optional, damit Explain nicht selbst zu einer großen RAM-Quelle wird. Ein Explain-Eintrag ist kein Ersatz für den tatsächlichen Beweis.

## 7. Binäres Produkt, Wire-IR und öffentliche API

Sublang als ausführbare Binary, binär serialisierte IR und eine native Bibliotheks-ABI sind verschiedene Schnittstellen. Für die erste sprachübergreifende öffentliche Integration wird ein versioniertes Prozessprotokoll festgelegt; interne Emerald-Klassen/Objektlayouts werden nicht als öffentliche ABI exportiert. Eine spätere native C-ABI wird separat versioniert, mit opaken Handles und eindeutigem Ownership für Ergebnisse/Fehler, ohne öffentliche interne Struct-Layouts.

### Prozessprotokoll, erster Entwurf

1. Hello/Capabilities: Protokoll-Major/Minor, lesbare/schreibbare Schema-Versionen, unterstützte High-/Low-Stufen, Extensions mit Versionen, Passes, Targets und Provider-Fähigkeiten.
2. Submit: RequestId, immutable Module-Snapshot, Target-/Provider-Auswahl, SemanticProfiles und Pipeline-Optionen.
3. Result: akzeptierter/effektiver Vertrag, neue Snapshot-/Revisions-IDs, Prüfergebnisse, Diagnosen, Explain-Entscheidungen und angeforderte Ausgabeartefakte.

Unbekannte erforderliche Features oder inkompatibles Major-Schema werden vor Optimierung abgelehnt. Optionale nichtsemantische Metadaten dürfen nur entsprechend ausgehandelter Regeln übersprungen werden. Pflichtoperationen nie ignorieren; Extension-Pässe brauchen Verständnis oder einen gültigen Erhaltungsvertrag. Kein stilles Downgrade auf andere Sprachregeln oder Speichermodi.

### Anforderungen an die Wire-Repräsentation

- Eigenständige Wire-Version und IR-Schema-Version; keine Gleichsetzung mit Architektur v0.4.
- Magic, feste Byteordnung und integer-/length-kodierte Frames/Sections; genaue Feldnummern und Encoding folgen mit A.2, vor Veröffentlichung. Keine native Struct-Serialisierung.
- IDs und Referenzen mit eindeutigem Modul-/Funktionsbereich, Snapshot und Revision; stabil im Snapshot, Remapping bei Transformation explizit. Keine Prozessadressen.
- Bitgenaue Integer-/FP-Konstanten, String-/Byte-Längen, Typen, Source-Spans, Extensions und Profile.
- Grenzen für Frame-/Tabellengrößen, definierte Fehler bei unvollständigem Input, Request-Lebenszyklus und klarer Besitz der Resultatdaten; keine unbegrenzte Materialisierung des Moduls.
- Semantisch deterministischer Export bei gleichem Snapshot. Dump-Ausgabe ist eine getrennte menschenlesbare Darstellung und kein Wire-Vertrag.

Noch kein öffentliches Versionskompatibilitätsversprechen: Erst ein implementierter Reader/Writer mit Negotiation und festem Encoding bildet eine veröffentlichbare Schnittstelle. Die vorhandenen Builder-Beispiele bleiben unverändert schema=1-Dumps.

## 8. Dynamisch typisierte Sprachen: verbindlicher Integrationsfall

Ein statisch typisierter IR-Kern schließt dynamische Sprachen nicht aus: `DynamicValue` ist ein IR-Typ mit Tags/Repräsentationsvertrag, dessen Laufzeitinhalt erst zur Ausführung bekannt ist. AOT nach LLVM ist der erste Zielpfad; JIT/Deoptimierung ist separat.

Die Dynamic-Erweiterung modelliert mindestens Tags, Tests, geprüfte Unbox/Box, dynamischen Dispatch, Property-/Index-Zugriffe, Closures/Captures und Runtime-Fallbacks. Numeric-Promotion, Overflow, Equality, Truthiness, String-/Property-Regeln und Fehlerverhalten kommen aus einem versionierten Sprachprofil. Es gibt keine universelle „Python/JS-Semantik“ im Core.

Heap-/Immediate-Repräsentation, bewegliche Referenzen, Roots und mögliche Safepoints sind explizit. Ein dyn-Wert ist nicht automatisch pointerfrei oder NoAlias. Dynamische Property-Zugriffe können Getter/Proxies/Usercode ausführen; ihre Effekte bleiben ohne Nachweis unknown. Shape-Spezialisierungen benötigen Guards, Mutation-/Invalidierungsverträge und den korrekten langsamen Pfad. Reflection/eval/FFI werden als konkrete Fähigkeiten angegeben; fehlende Pflichtfähigkeiten führen zur Diagnose.

### Erster realer Dynamic-Slice nach der kleinen statischen LLVM-Strecke

Ein kleines AOT-Frontend mit dokumentierter Teilmenge liefert dynamische Werte und denselben Sublang-Core: i64 und f64 sowie einen heapfähigen String-Wert, Type Tests, dynamische Addition mit definierten Promotions-/Fehlerregeln und Runtime-Fallback, einen dynamischen Property-/Index-Zugriff und einen Closure-Call. Das konkrete Minisprachprofil wird vor Implementierung festgelegt; es gibt keine Behauptung vollständiger JS-/Python-Kompatibilität.

Der Slice muss auch einen tatsächlich heapfähigen dyn-Wert über einen möglicherweise allokierenden Call hinweg korrekt erhalten. Ein reiner Tagged-Int-Demo beweist keine GC-/Lifetime-Integration. Zusätzlich wird mindestens ein Effekt-/Alias-Blocker sichtbar erklärt. Mit einem zunächst nicht bewegenden Provider wird keine bewegende-GC-Unterstützung behauptet; deren Root-Relocation ist ein eigener Provider-Abnahmepunkt.

Ein vorhandener GC kann über Integration bleiben. Flow Managed wird nur angeboten, wenn der konkrete Provider die benötigte Sharing-/Cycle-/Finalizer-/Weak-/Thread-Semantik vollständig abdeckt. Dynamische Typisierung allein verlangt keinen universellen Collector, erlaubt aber auch kein Weglassen dieser Semantik.

## 9. Umsetzungsetappen und Abnahme

- **A.1 ergänzen:** erstklassige EffectSummary-/Provenance- und Alias-/Location-Datensätze mit konservativen Defaults, getrennte Prüfdimensionen und gemeinsame Diagnose-/Explain-Referenzen. Noch keine umfassende interprozedurale Beweisanalyse behaupten.
- **A.2:** versionierter Passmanager-/Snapshot-Vertrag und feste Wire-Spezifikation, minimaler Reader/Writer mit Capability-Negotiation und begrenzten Roundtrips. Keine LLVM- oder GC-ABI aus zufälligen Emerald-Layouts ableiten.
- **B:** kleine statische LLVM-Strecke zunächst ohne Unwinding und ohne nicht unterstützte Dynamic-Features; korrekte Basispipeline auch ohne Flow.
- **B.1 Dynamic:** den beschriebenen tatsächlichen AOT-Dynamic-Slice einbinden, anschließend passweise erweitern. Jetzt verbindliches Ziel, nicht als unbegrenzte zukünftige Option verschieben.
- **EH/Provider-Ausbau:** explizite Exception-CFGs und Cleanup-Modell implementieren, dann passenden LLVM-EH-Adapter und Runtime-Abdeckung abnehmen. Sprachen, die Exceptions verlangen, bleiben bis dahin unsupported.

Pro neuer Grenze nur aussagekräftige gebündelte Prüfungen. Keine neue große Benchmark-Serie. Jeder Compiler-/Selfhost-Lauf bleibt in einer Sandbox mit maximal 8 GB RAM, bevorzugt 6 GB ohne Swap. Diese Vertragsaktualisierung führt selbst keinen Compiler aus und meldet keine neue implementierte Funktion.
