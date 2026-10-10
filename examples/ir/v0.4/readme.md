# Sublang v0.4 — überarbeitete Zielbeispiele

Diese Dateien sind **vollständige illustrative Zielmodule**, keine heute einlesbare IR. Das öffentliche binäre Encoding und die native ABI sind damit nicht implementiert. Details und gemeinsam definierte Notation stehen in [extended-ir.md](../extended-ir.md). Effekte, Verifikation und Beweise in diesen Dateien sind erwartete Entwurfsresultate, keine tatsächlichen Analyseläufe.

| Datei | Inhalt |
| --- | --- |
| [01-procedural.sublang-ir](01-procedural.sublang-ir) | checked i64, freie Funktionen, Effektsummaries |
| [02-objects.sublang-ir](02-objects.sublang-ir) | OO-Interface, offene Zielmenge, deklarierte und bewiesene Effekte |
| [03-managed-high.sublang-ir](03-managed-high.sublang-ir) | Flow Managed mit gesonderten Lifetime-/Ownership-Bezügen |
| [04-managed-low.sublang-ir](04-managed-low.sublang-ir) | Plan-konsumierende Low IR, Effekte nach Lowering |
| [05-gc-integration.sublang-ir](05-gc-integration.sublang-ir) | bewegender GC, aktualisierte Roots und Write Barrier |
| [06-bond-cycles.sublang-ir](06-bond-cycles.sublang-ir) | Bond-Graph und Cycle-Provider |
| [07-dynamic.sublang-ir](07-dynamic.sublang-ir) | dynamische Zahlen/Strings, Heap-Handles und Fallback |
| [08-closure.sublang-ir](08-closure.sublang-ir) | Closure mit Value-Capture und Effektvertrag |
| [09-explain.sublang-ir](09-explain.sublang-ir) | unbekannter Call, GC-Escape und Explain-Bezug |
| [10-exceptions.sublang-ir](10-exceptions.sublang-ir) | Invoke, normale/exceptional Kanten, Cleanup, Catch und Resume |
| [11-ownership-transfer.sublang-ir](11-ownership-transfer.sublang-ir) | Ownership-Transfer über lexikalisches Scope-Ende |

[LLVM-Illustration](managed-illustrative.ll) gehört zu Managed High/Low. Pläne, Explain-, Pass- und Protokollberichte stehen zusammenhängend in [extended-ir.md](../extended-ir.md), mit denselben Modul-/Entity-IDs. Sie bilden keinen separaten Parser oder Validator.

Die [aktuellen Builder-Beispiele](../readme.md) bleiben getrennt: schema=1, echte erzeugte Dumps, strukturgeprüft; Semantik/Lifetime nicht geprüft. Für die v0.4-Überarbeitung wurde kein Compiler ausgeführt.
