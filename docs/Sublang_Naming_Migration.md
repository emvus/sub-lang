# Sublang / Optimind / HyperAlloc Flow — technische Migration

## Aktueller Stand

Eigenständiger Checkout: `../Sublang`, Remote `https://github.com/emvus/sub-lang`, ursprünglicher Remote-Stand `01f25358a9951fb20988eb8793f437fcfbb93499` (enthielt nur LICENSE). LICENSE wurde beibehalten. Sublang-Implementierung ausschließlich in Emerald `.ems`; keine neue fusionierte Sprache oder Dateiendung.

Sublang bleibt sprachunabhängige Compilerplattform. Optimind bezeichnet ihre allgemeine Analyse-/Optimierungsengine; dieser Name ist kein Nachweis einer bereits fertigen Passpipeline. HyperAlloc Flow bleibt optional. Architektur, IR-Schema=1, Overflow-/FP-Regeln und fehlende Lifetime-/LLVM-Funktionen wurden durch die Migration nicht umdefiniert.

## Technische Zuordnung

| Bisher | Kanonisch |
| --- | --- |
| EOS / Emerald Optimization System | Sublang |
| eos::* / Eos* | sublang::* / Sublang* |
| EOS-* Diagnosecodes | SUBLANG-* |
| examples/eos und EOS-Dokumente | examples/ir und docs/Sublang_* im eigenen Repo |
| .eos Dump / .eosir Entwurf | .sublang Dump / .sublang-ir Entwurf |
| Emerald Flow | HyperAlloc Flow |
| emerald::compiler::flow | emerald::compiler::hyperallocflow |
| Flow* / NativeFlow* | HyperAllocFlow* / NativeHyperAllocFlow* |
| emerald_flow_* | hyperalloc_flow_* |
| EMERALD_FLOW_* | HYPERALLOC_FLOW_* |
| --explain-flow / --flow-strict | --explain-hyperalloc-flow / --hyperalloc-flow-strict |
| emerald.sh flow | emerald.sh hyperalloc-flow |
| allgemeine Optimierungsengine | Optimind |

`.sublang` und `.sublang-ir` sind Dokumentations-/IR-Dateien, keine neue Source-Sprachendung. Die Source-Dateien bleiben `.ems`. Vorgesehene Plattformoptionen heißen `--sublang-flow` und `--sublang-memory`; die Dokumentation benennt HyperAlloc-Speichermodi `hyperalloc-managed` und `hyperalloc-integration`. Diese Plattform-CLI existiert noch nicht; es wird kein funktionsloser Wrapper als fertiger Compiler angeboten.

## Repository-Grenze

Der neutrale Core liegt nur in `Sublang/src/sublang/`. Beispiele, Harness, Schema-/Protokoll-/Effekt-/Dynamic-Verträge liegen ebenfalls im eigenen Repo. Emerald behält Frontend, Compiler, Stdlib und seine konkrete Runtime-Integration. Ein Sublang-Sandbox-Runner mountet Sublang und die externe Emerald-Toolchain getrennt read-only; `SUBLANG_EMERALD_ROOT` konfiguriert die Toolchain, `SUBLANG_SANDBOX_IMAGE` das Containerimage.

Die vorhandene C-Runtime gehört zur bestehenden Emerald-Integration. Sie wurde nicht als neue C-Implementierung des Sublang-Cores hineinkopiert. Der spätere neutrale HyperAlloc-Provider muss weiterhin anhand der Plattformverträge implementiert werden.

## Kompatibilität statt ABI-Bruch

Installierte Compiler-Binaries bleiben unverändert. Ihr Code kann alte Runtime-Symbole referenzieren. `runtime/src/hyperalloc_flow/legacy_abi.c` enthält deshalb portable Forwarder auf denselben kanonischen Allocatorzustand; keine zweite Runtime. `runtime/hyperalloc_flow_legacy.h` ist ein ausdrücklich opt-in Header für alte C-Quellen. Neue Runtime-/Emitter-/Stdlib-/Testquellen verwenden die neuen Namen.

Runtime-Env-Auswertung verwendet neue Variablen zuerst und akzeptiert fehlende alte Werte als Fallback. Ein explizites neues `0` hat Vorrang. Alte Emerald-CLI-Flags und das Shellkommando `flow` bleiben eng begrenzte Aliase; neue Helptexte nennen die kanonischen Namen. Historische Binaries, Messlogs, Backups und Stage0-Snapshots werden nicht als aktive Quelltexte umgeschrieben. Das ursprüngliche technische Overview und sein SHA bleiben historische Provenienz; die umbenannte aktive Kopie ist redaktionell bearbeitet.

## Gezielte Verifikation

Der eigenständige Sublang-Harness besteht alle fünf Fälle, alle sieben Beispielmodule bestehen Struktur-/Typ-/Dominanzprüfung; Dumps wurden aus dem Lauf neu erzeugt. Ein einziger gebündelter 6-GB-Sandbox-Lauf, kein Swap, kein Netzwerk. Lifetime bleibt not_checked, codegenReady bleibt false. Die erweiterten Beispiele bleiben Zielsyntax.

Die zusätzliche Emerald-/Runtime-Abnahme wird unten ergänzt. Kein großer Bootstrap und keine Benchmark-Serie. Keine installierten Compiler wurden ersetzt.

## Sicherung

Vorherige Quell-/Dokumentfassungen der ersten Umbenennungsrunde: `/tmp/sublang-before-naming-migration.tar`. Der ältere vollständige Projekt-Backup vor EOS liegt weiterhin außerhalb des Arbeitsprojekts. Diese Migration ist kein neuer Performance- oder Feature-Nachweis.

### Ergebnis der Emerald-/Runtime-Abnahme

Ein zweiter gebündelter Sandbox-Lauf (6 GB, kein Swap, kein Netzwerk) war erfolgreich:

- Kanonische und alte Runtime-Symbole allokieren/freigeben über denselben Zustand; null Live- und Invalid-Release-Zähler nach dem Cross-ABI-Fall.
- Der umbenannte Emerald-Compiler baut vollständig aus Main.ems mit der vorhandenen stabilen Toolchain.
- Der neue Compiler baut ein i64-Programm mit --explain-hyperalloc-flow; Report trägt HyperAlloc Flow, Ausgabe 4000000000.
- Der bewusst erhaltene --explain-flow-Alias liefert dieselbe Programmausgabe.

Kein mehrstufiger Selfhost-Determinismus-Gate, keine neue Benchmarkmessung. Installierte Compiler-Binaries bleiben unverändert. Die neuen CLI-Namen sind in der verifizierten neuen Compilerquelle implementiert und standen im temporären Prüfbuild zur Verfügung.
