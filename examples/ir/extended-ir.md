# Erweiterte Sublang IR — vollständige Entwurfsbeispiele

**Status: vorgeschlagene Notation, keine ausführbaren `.sublang`-Programme.**

Diese Beispiele konkretisieren den Zielvertrag v0.4 (Sublang_IR_Contracts.md), die v0.3-Grundlage und das Technical Overview. Operationen, Profilattribute, Provider-APIs und Planformate in diesem Dokument sind noch nicht als öffentliche API implementiert. Die derzeit tatsächlich erzeugbaren Dumps stehen daneben in `01-*.sublang` bis `07-*.sublang`.

Die nummerierten Module sind eigenständige Entwurfsbeispiele. Die Berichte beziehen sich auf die jeweils genannten Module; symbolische Target-/Runtime-Verträge sind explizite Integrationsabhängigkeiten. `!T` bezeichnet einen Typ, `%x` einen funktionslokalen SSA-Wert, `^b` einen Block, `@name` eine Moduldefinition. Blockargumente übernehmen Phi-Funktionen. Deklarationen wie `runtime`, `provider`, `profile` sind hier erklärende Vertragssyntax, keine festgelegte Textgrammatik. Target- und Runtime-Abhängigkeiten werden explizit angegeben. Konkrete Datensatzfelder werden bei der Implementierung versioniert.

### Einheitliche v0.4-Notation

`effects @unknown { default=unknown origin=AssumedConservative }` setzt **jedes** nicht näher bekannte Effektfeld konservativ auf unknown. Ein spezialisiertes Summary erbt davon und überschreibt nur ausdrücklich genannte Felder. `origin=Declared trusted=...` bezeichnet einen gebundenen Provider-/Profilvertrag; `origin=Proven analysis=... revision=N` bezeichnet einen beispielhaften Analysebericht desselben Snapshots. Keiner der dargestellten Beweise wurde bereits durch Sublang ausgeführt.

Jede Funktion und jeder Call verweist auf ein Summary. Effektbehaftete Built-in-Operationen verwenden explizite versionierte Opcode-Verträge aus der angeforderten Extension; fehlende Verträge führen zur Diagnose. `reads/writes=local(...)` bleibt ein echter Speichereffekt. „Keine globalen Writes“ heißt nicht „keine Writes“.

Die vollständigen Modulblöcke stehen zusätzlich als einzelne [v0.4-Dateien](v0.4/readme.md). Diese `.sublang-ir`-Dateien sind **Zielnotation**, keine heutigen Builder-Dumps und kein veröffentlichtes Eingabeformat.

## 1. Prozedurale Sprache ohne Flow: checked i64

Das Frontend kann eine C-artige, funktionale oder andere Sprache implementieren. Dieses konkrete Profil wählt checked i64 und abort, nicht implizit die Regeln einer bestimmten Quellsprache. Eine Sprache mit wrap, Exceptions oder anderen Regeln braucht einen passenden eigenen Vertrag.

```text
module @procedural stage=High schema=planned revision=1 {
  require Core@planned
  profile @checked {
    integers = signed_i64
    overflow = checked
    division_by_zero = abort
    division_min_by_minus_one = abort
    fp = ieee754_binary64_rne_strict
    unwind = none
  }
  failure @overflow { behavior=abort; signature=() -> never }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @checked_effects inherits=@unknown {
    mayAllocate=false; mayEscape=false; mayThrow=false; mayFail=true
    reads=none; writes=none; synchronization=none; observable=none
    mayDiverge=false
    origin=Proven analysis=@body_effects revision=1
  }

  func @add(%a: !i64, %b: !i64) -> !i64
      profile=@checked linkage=internal cc=sublang
      effects=@checked_effects {
    ^entry:
      %sum = core.int.add %a, %b overflow=checked failure=@overflow
      core.return %sum
  }

  func @main() -> !i64 profile=@checked linkage=internal cc=sublang effects=@checked_effects {
    ^entry:
      %a = core.const.i64 20
      %b = core.const.i64 22
      %r = core.call.direct @add(%a, %b) effects=@checked_effects
      core.return %r
  }
  entry = @main
}
pipeline { flow=off; memory=language; backend=llvm }
```

Ergebnis 42. Auch wenn `%sum` ungenutzt wäre, darf ein möglicherweise fehlschlagender Call nicht einfach entfernt werden. Bei `2_000_000_000 + 2_000_000_000` ergibt dieses i64-Profil 4_000_000_000; außerhalb des i64-Bereichs wird der Fehlervertrag ausgeführt. `flow=off` deaktiviert weder die Semantik noch notwendige Sicherheitsprüfungen.

## 2. OO: Identität und virtueller Dispatch

```text
module @objects stage=High schema=planned revision=1 {
  require Core@planned, Object@planned
  profile @oo { integers=signed_i64; overflow=checked; unwind=none }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @slot_effects inherits=@unknown {
    mayThrow=false origin=Declared trusted=@oo.interface_contract
  }
  effects @read_effects inherits=@unknown {
    mayAllocate=false; mayEscape=false; mayThrow=false; mayFail=false
    reads=argument0.value; writes=none; synchronization=none; observable=none
    mayDiverge=false
    origin=Proven analysis=@Counter_read_body revision=1
  }
  interface !Readable {
    slot read: (borrow_read self) -> !i64 effects=@slot_effects
  }
  class !Counter implements !Readable identity=observable {
    field value: !i64 mutable
    slot read = @Counter.read
  }

  func @Counter.read(%self: borrow_read !ref<!Counter>) -> !i64
      profile=@oo methodOf=!Counter effects=@read_effects {
    ^entry:
      %r = object.field.read %self, !Counter.value
      core.return %r
  }

  func @readAny(%input: borrow_read !interface_ref<!Readable>) -> !i64
      profile=@oo effects=@slot_effects
      dispatch_world=open {
    ^entry:
      %r = object.call.interface %input, !Readable.read()
           effects=@slot_effects contract=!Readable.read
      core.return %r
  }
}
```

Das Interface-Profil verlangt, dass Implementierungen nicht unwinden; weitere Effekte bleiben unbekannt. Ein neues unbekanntes Implementierungsziel verhindert unbewiesene Devirtualisierung und Escape-Optimierungen. Ein `borrow_read` des Receivers bedeutet nicht automatisch, dass der Call weder globale Zustände ändert noch allokiert. Nur mit vollständiger Zielmenge oder einem geprüften Guard/Fallback darf Sublang daraus direkte Aufrufe machen. Das dynamische Objekt behält seine Identität.

## 3. Flow Managed: temporäres Objekt und Plan bis LLVM

### High IR

```text
module @temporary stage=High schema=planned revision=7 {
  require Core@planned, Object@planned, Memory@planned
  profile @simple {
    integers=signed_i64; overflow=checked; unwind=none
    object_identity=observable; finalizers=none
  }
  failure @overflow { behavior=abort; signature=() -> never }
  class !Point identity=observable {
    field x: !i64 immutable
    field y: !i64 immutable
  }
  provider @flow_simple {
    stack_refs_supported=true; moving_gc=false; finalizers=none
    object_allocation_failure=abort; abort_cleanup=not_observable
  }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @sum_effects inherits=@unknown {
    mayAllocate=true; mayEscape=false; mayThrow=false; mayFail=true
    reads=local(%p); writes=local(%p); synchronization=none; observable=none
    mayDiverge=false
    origin=Proven analysis=@sum_body revision=7
  }
  func @sum() -> !i64 profile=@simple linkage=internal cc=sublang effects=@sum_effects {
    ^entry:
      %scope = memory.scope.begin
      %x = core.const.i64 20
      %y = core.const.i64 22
      %p = object.new !Point(%x, %y) result=owned scope_hint=%scope
      %a = object.field.read %p, !Point.x
      %b = object.field.read %p, !Point.y
      %r = core.int.add %a, %b overflow=checked failure=@overflow
      memory.drop %p
      memory.scope.end %scope
      core.return %r
  }
}
pipeline { flow=on; memory=hyperalloc-managed; provider=@flow_simple }
```

Hier wird die Identität tatsächlich nie beobachtet. Folded kann das Objekt vollständig entfernen, wenn zusätzlich alle Effekte dies erlauben. Für die folgende **Local-Demonstration ist Folded gezielt deaktiviert**. Die Strategie ist eine Passentscheidung und kein Sprachversprechen.

### MemoryPlan, schematisch

```text
plan @temporary_sum {
  module_revision=7
  function=@sum
  entity_key=(@temporary, revision=7, @sum, %p)
  target=x86_64-linux
  target_layout={pointer_bits=64; i64_size=8; i64_align=8}
  provider=@flow_simple
  provider_contract={stack_refs_supported=true; finalizers=none; moving_gc=false}
  storage[%p]={strategy=Local; bytes=16; alignment=8; header=none}
  layout[!Point]={x:offset0:i64; y:offset8:i64}
  evidence={
    effects=@sum_body:revision7
    aliases={location(%p) NoAlias external_locations}
    ownership={%p:owned; transfer:none; drop_count:1_on_normal_exit}
    lifetime={last_use:%b; live_borrows_at_drop:none; escapes:none}
    identity={observations:none}; initialization={x:valid; y:valid}
  }
  cleanup={normal_return:end_lifetime; abort:process_termination}
  verification={structure:valid; semantics:valid; memory_lifetime:valid}
  status=illustrative_expected_report
}
```

Der Plan stützt sich auf gesonderte Ownership-/Lifetime-Analysen. `scope_hint` ist nur ein Kandidat; `scope.end` allein rechtfertigt weder Drop noch Stack-Platzierung. Die hier dargestellten Prüfergebnisse sind erwartete Berichte des Entwurfs.

Die 16 Bytes sind hier **zwei Felder**, kein Flow-Objektheader. Das Layout ist nur für diesen Plan und dieses Target zulässig. Layout-Beobachtung durch FFI oder Reflection würde zusätzliche Bedingungen verlangen. Revision, Ziel und Provider sind Teil der Gültigkeit; eine andere Revision darf den Plan nicht ungeprüft verwenden.

### Low IR, schematisch

```text
module @temporary_low stage=Low revision=8 consumes_plan=@temporary_sum {
  require Core@planned, Memory@planned
  target = x86_64-linux
  failure @overflow { behavior=abort; provider=@abort_runtime }
  effects @low_effects {
    default=unknown origin=AssumedConservative
    mayAllocate=false; mayEscape=false; mayThrow=false; mayFail=true
    reads=local(%slot); writes=local(%slot); synchronization=none
    observable=none; mayDiverge=false
    facts_origin=Proven analysis=@low_sum_body revision=8
  }
  func @sum() -> !i64 cc=sublang effects=@low_effects {
    ^entry:
      %slot = memory.stack.alloc bytes=16 align=8
      memory.lifetime.start %slot bytes=16
      memory.store.i64 %slot offset=0, 20 align=8
      memory.store.i64 %slot offset=8, 22 align=8
      %a = memory.load.i64 %slot offset=0 align=8
      %b = memory.load.i64 %slot offset=8 align=8
      %r = core.int.add %a, %b overflow=checked failure=@overflow
      memory.lifetime.end %slot bytes=16
      core.return %r
  }
}
```

Der Lowering-Schritt dokumentiert, dass er den High-Plan aus Revision 7 konsumiert und daraus Revision 8 erzeugt. Der Low-Verifier prüft neue Entity-Zuordnung und Layoutumsetzung. Der LLVM-Emitter darf kein eigenes abweichendes Point-Layout erfinden.

### LLVM IR als konkrete Illustration

Das folgende Beispiel entspricht diesem 64-Bit-Ziel und dem abort-Vertrag. Es wurde hier nicht durch LLVM assembliert. Die endgültige LLVM-Version/TargetDataLayout legt der Backend-Adapter fest.

```llvm
target triple = "x86_64-unknown-linux-gnu"

declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture)
declare void @sublang_abort_overflow() noreturn nounwind

define internal i64 @sum() nounwind {
entry:
  %slot = alloca [2 x i64], align 8
  call void @llvm.lifetime.start.p0(i64 16, ptr %slot)
  %x = getelementptr [2 x i64], ptr %slot, i64 0, i64 0
  %y = getelementptr [2 x i64], ptr %slot, i64 0, i64 1
  store i64 20, ptr %x, align 8
  store i64 22, ptr %y, align 8
  %a = load i64, ptr %x, align 8
  %b = load i64, ptr %y, align 8
  %checked = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %a, i64 %b)
  %r = extractvalue { i64, i1 } %checked, 0
  %overflow = extractvalue { i64, i1 } %checked, 1
  br i1 %overflow, label %failed, label %done
failed:
  call void @sublang_abort_overflow()
  unreachable
done:
  call void @llvm.lifetime.end.p0(i64 16, ptr %slot)
  ret i64 %r
}
```

LLVM kann diesen einfachen Fall weiter zu `ret i64 42` reduzieren. Das ist korrekte allgemeine Optimierung, keine besondere Benchmark-Regel. `nsw` allein würde den geforderten Fehlerpfad nicht implementieren.

## 4. Flow Integration: bestehender bewegender GC

```text
module @integrated stage=High schema=planned revision=1 {
  require Core@planned, Object@planned, Memory@planned, GC@planned
  profile @host {
    integers=signed_i64; unwind=none; finalizers=none
    object_identity=observable; gc=host_moving
  }
  runtime @host_gc {
    moving=true; roots=updateable_handles
    safepoints=explicit_and_allocating_calls
    write_barrier=required_on_reference_store
    allocation_failure=abort
  }
  provider @integration { runtime=@host_gc; collector_replacement=false }
  class !Node identity=observable {
    field next: !nullable_ref<!Node> mutable
  }

  effects @unknown { default=unknown origin=AssumedConservative }
  effects @gc_effects inherits=@unknown {
    mayAllocate=true; mayEscape=false; mayThrow=false; mayFail=true
    reads=runtime+local_nodes; writes=runtime+local_nodes
    synchronization=provider_defined; observable=none; mayDiverge=unknown
    origin=Declared trusted=@host_gc
  }
  func @linkTwo() -> !i64 profile=@host effects=@gc_effects {
    ^entry:
      %roots = gc.root_scope.begin runtime=@host_gc
      %a = gc.alloc_rooted !Node(next=null) roots=%roots
      %b = gc.alloc_rooted !Node(next=null) roots=%roots
      gc.store_ref_with_barrier base_root=%a field=!Node.next value_root=%b
      gc.safepoint runtime=@host_gc
      %currentA = gc.root.load %a
      %currentB = gc.root.load %b
      %next = object.field.read %currentA, !Node.next
      %same = object.ref.equal %next, %currentB
      %answer = core.select %same, i64(1), i64(0)
      gc.root_scope.end %roots
      core.return %answer
  }
}
pipeline { flow=on; memory=hyperalloc-integration; provider=@integration }
```

`gc.alloc_rooted` ist eine vorgeschlagene Provider-Operation: Allokation und Veröffentlichung des Handles sind GC-sicher, Initialisierung setzt das Ref-Feld auf null. Der Barrier-Vertrag nimmt Handles und löst aktuelle Adressen auf. Nach einem Safepoint werden Referenzen erneut aus aktualisierten Roots geladen; veraltete rohe Pointer werden nicht weiterbenutzt. Zwischen diesen Loads und dem letzten Feldzugriff liegt hier kein weiterer Safepoint.

Ergebnis 1. Die Root-Scope-Ende-Operation gibt Handles frei, nicht eigenmächtig die Heap-Objekte. Der bestehende GC verwaltet deren Speicher. Ohne kompatiblen Root-/Barrier-Vertrag wird dieser Modus abgelehnt. Flow darf kompatible Optimierungen anwenden, aber nicht einfach den Collector ersetzen.

## 5. Flow Managed mit Sharing/Zyklen: Bond

```text
module @cycles stage=High schema=planned revision=1 {
  require Core@planned, Object@planned, Memory@planned
  profile @graph {
    unwind=none; finalizers=none; weak_references=none
    threads=single; object_identity=observable
  }
  provider @bond {
    sharing=true; cycles=true; weak_references=false; finalizers=false
    edge_updates=tracked; collection_timing=unobservable
  }
  class !Node identity=observable {
    field next: !nullable_shared_ref<!Node> mutable
  }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @bond_effects inherits=@unknown {
    mayAllocate=true; mayThrow=false; mayFail=true
    mayEscape=runtime_graph; reads=runtime+local_graph; writes=runtime+local_graph
    synchronization=none; observable=none; mayDiverge=unknown
    origin=Declared trusted=@bond
  }
  func @cycle() -> !i64 profile=@graph effects=@bond_effects {
    ^entry:
      %a = memory.shared.new !Node(next=null) provider=@bond
      %b = memory.shared.new !Node(next=null) provider=@bond
      memory.shared.edge.set %a, !Node.next, %b provider=@bond
      memory.shared.edge.set %b, !Node.next, %a provider=@bond
      memory.shared.release %a provider=@bond
      memory.shared.release %b provider=@bond
      core.return i64(0)
  }
}
pipeline { flow=on; memory=hyperalloc-managed; provider=@bond }
```

Edge-Operationen aktualisieren Sharing-/Cycle-Metadaten. `release` gibt jeweils einen externen Owner frei; die beiden internen Kanten bestehen zunächst weiter. Der Provider muss den unerreichbaren Zyklus erkennen und freigeben können. Die IR behauptet keine sofortige Collection. Mit beobachtbaren Finalizern, Weak-Refs oder Threads wäre dieser begrenzte Provider unzureichend; Sublang darf diese Features nicht still verwerfen.

## 6. Dynamische Sprache: Tags, beweglicher Heap und Runtime-Fallback

Das konkrete Minisprachprofil erlaubt i64, f64 und immutable Strings. Addition addiert Zahlen mit i64→f64-Promotion oder konkateniert zwei Strings; i64-Overflow führt in den Runtime-Fallback, dessen Ergebnis hier f64 ist. Andere Kombinationen aborten. Das ist bewusst eine eigene Minisprachsemantik, keine implizite Python-/JS-Regel.

```text
module @dynamic stage=High schema=planned revision=1 {
  require Core@planned, Dynamic@planned, Memory@planned, GC@planned
  profile @dynamic_language {
    values={i64,f64,immutable_string}; overflow=runtime_numeric_dispatch
    numeric_promotion=i64_to_f64; string_add=concatenate; invalid_add=abort
    unwind=none; gc=host_moving
  }
  runtime @dynamic_runtime {
    roots=updateable_handles; moving=true; safepoints=allocating_calls
    small_i64_box=immediate; errors=abort
    add_contract=@dynamic_language; root_drop=nonallocating_nonthrowing
  }
  provider @integration { runtime=@dynamic_runtime; collector_replacement=false }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @tag_effects inherits=@unknown {
    mayAllocate=false; mayEscape=false; mayThrow=false; mayFail=false
    reads=argument_root_handles; writes=none; synchronization=none; observable=none
    mayDiverge=false origin=Declared trusted=@dynamic_runtime.tag_contract
  }
  effects @add_effects inherits=@unknown {
    mayAllocate=true; mayThrow=false; mayFail=true
    escape.arguments=none; escape.result=owned_rooted
    reads=arguments+runtime; writes=runtime
    synchronization=provider_defined; observable=none; mayDiverge=unknown
    origin=Declared trusted=@dynamic_runtime.add
  }
  extern func @addSlow(!dyn_root, !dyn_root) -> owned !dyn_root
      profile=@dynamic_language cc=provider contract=@dynamic_runtime.add
      effects=@add_effects

  func @add(%a: borrow_read !dyn_root, %b: borrow_read !dyn_root)
      -> owned !dyn_root profile=@dynamic_language effects=@add_effects {
    ^entry:
      %aInt = dynamic.root.tag.is %a, i64 effects=@tag_effects
      %bInt = dynamic.root.tag.is %b, i64 effects=@tag_effects
      %both = core.bool.and %aInt, %bInt
      core.cond_branch %both, ^integers, ^slow
    ^integers:
      %x = dynamic.root.unbox.i64 %a proof=%aInt effects=@tag_effects
      %y = dynamic.root.unbox.i64 %b proof=%bInt effects=@tag_effects
      (%sum, %overflow) = core.int.add_with_overflow %x, %y
      core.cond_branch %overflow, ^slow, ^box(%sum)
    ^box(%value: !i64):
      %r = dynamic.root.box.i64 %value runtime=@dynamic_runtime result=owned
      core.return_owned %r
    ^slow:
      %r = core.call.external @addSlow(%a, %b) effects=@add_effects
           contract=@dynamic_runtime.add
      core.return_owned %r
  }

  func @main() -> !i64 profile=@dynamic_language effects=@add_effects {
    ^entry:
      %roots = gc.root_scope.begin runtime=@dynamic_runtime
      %a = dynamic.string.new_rooted bytes="hello" roots=%roots
      %b = dynamic.string.new_rooted bytes=" world" roots=%roots
      %joined = core.call.direct @add(%a, %b) effects=@add_effects
      gc.root.adopt_owned %joined into=%roots
      gc.safepoint runtime=@dynamic_runtime
      %current = dynamic.root.load %joined
      %length = dynamic.string.byte_length %current contract=@dynamic_runtime.no_safepoint_read
      gc.root_scope.end %roots
      core.return %length
  }
}
pipeline { flow=on; memory=hyperalloc-integration; provider=@integration }
```

Erwartetes Ergebnis 11. Die Runtime erhält Handles statt veralteter Heap-Pointer. Ergebnisse werden vor einem weiteren Safepoint in einen Root-Scope übernommen; `adopt_owned` ist nicht allokierend. Auch der Fastpath gibt einen owned Handle zurück. Der Byte-Length-Zugriff und das Root-Scope-Ende führen hier keinen Safepoint aus. Zwei rohe `!dyn`-Parameter allein hätten diesen bewegenden-GC-Vertrag nicht erfüllt.

`@add_effects` ist eine konservative Obergrenze: Ein einzelner Zahlen-Fastpath allokiert möglicherweise nicht, der Gesamtcall kann Strings allokieren und Runtime-Zustand ändern. Alias zu Runtime-Locations bleibt MayAlias, solange keine Analyse das präzisiert. Ein nicht unterstützter bewegender Provider führt zur Diagnose, nicht zu stiller Verwendung alter Adressen. Das Beispiel verlangt weiterhin keinen JIT.

## 7. Closure mit Capture-Lebensdauer

```text
module @closure stage=High schema=planned revision=1 {
  require Core@planned, Object@planned, Memory@planned, Closure@planned
  profile @functional { integers=signed_i64; overflow=checked; unwind=none }
  failure @overflow { behavior=abort; signature=() -> never }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @body_effects inherits=@unknown {
    mayAllocate=false; mayEscape=false; mayThrow=false; mayFail=true
    reads=none; writes=none; synchronization=none; observable=none
    mayDiverge=false origin=Proven analysis=@closure_body revision=1
  }
  effects @closure_effects inherits=@unknown {
    mayAllocate=true; mayEscape=false; mayThrow=false; mayFail=true
    reads=local_capture; writes=local_capture; synchronization=none; observable=none
    mayDiverge=false origin=Proven analysis=@closure_main revision=1
  }
  provider @closure_runtime { finalizers=none; allocation_failure=abort; moving_gc=false }
  record !Env { base: !i64 }

  func @body(%env: !Env, %arg: !i64) -> !i64 profile=@functional effects=@body_effects {
    ^entry:
      %base = object.record.get %env, !Env.base
      %r = core.int.add %base, %arg overflow=checked failure=@overflow
      core.return %r
  }
  func @main() -> !i64 profile=@functional effects=@closure_effects {
    ^entry:
      %env = object.record.make !Env(base=i64(40))
      %f = closure.make code=@body env=%env capture=value provider=@closure_runtime result=owned
      %r = closure.call %f(i64(2)) effects=@body_effects
      memory.drop %f
      core.return %r
  }
}
```

Ergebnis 42. Das Capture ist ein eigener Wert, kein Borrow auf einen später zerstörten Stack-Local. Bei einer tatsächlich entkommenden Closure mit borrowed Capture muss die Lifetime-Prüfung entweder die Lebensdauer belegen, eine semantisch zulässige Repräsentation wählen oder ablehnen. Eine automatische Kopie wäre bei beobachtbarer Identität/Mutation nicht allgemein korrekt.

## Alle acht Flow-Strategien in der IR

Die High IR beschreibt logische Objekte und Sprachregeln. Strategien stehen im Analyse-/MemoryPlan; Frontends müssen nicht acht spezielle Allokations-Opcodes erfinden.

| Strategie | Logisches Beispiel | Physische Umsetzung bei gültigem Nachweis |
| --- | --- | --- |
| Folded | temporäres Point, nur Felder gelesen | skalare SSA-Werte; keine Objektallokation |
| Inline | List von Werten mit unobservable Identität | Elemente direkt im Buffer; Stride/Layout aus Plan |
| Local | nicht entkommendes Objekt im Scope | Stack-Slot, Lifetime-Markierungen, notwendige Cleanup-Aktionen |
| Pool | wiederholte, abgeschlossene Objektlebensdauern | Slot nach Ende sämtlicher alter Referenzen wiederverwenden |
| Shard | Gruppe mit gemeinsamem Lifetime-Ende | Region allokieren, notwendige Drops, dann Region freigeben |
| Root | eindeutiger Owner mit Transfer | Ownership übertragen; genau einmal auf jedem relevanten Pfad droppen |
| Bond | geteilte Objektgraphen, ggf. Zyklen | kompatibler Sharing-/Cycle-Provider und getrackte Kanten |
| Static | unveränderliche geeignete Daten/Literale | konstante Globals; Identitäts-/Internierungsregeln erhalten |

### Beispiel eines gemischten Plans

```text
plan @mixed revision=12 target=@target provider=@flow {
  entity(@f,%point)  -> Folded evidence=@point_scalar_proof
  entity(@f,%values) -> Inline element_layout=@value_layout evidence=@copy_semantics
  entity(@f,%temp)   -> Local  evidence=@scope_proof
  entity(@f,%task)   -> Pool   evidence=@dead_before_reuse
  entity(@f,%batch)  -> Shard  evidence=@common_lifetime
  entity(@f,%owner)  -> Root   evidence=@unique_transfer
  entity(@f,%graph)  -> Bond   evidence=@sharing_contract
  entity(@f,%text)   -> Static evidence=@immutable_static_lifetime
}
```

Die Beweisreferenzen sind hier Platzhalter für echte versionierte Analyseergebnisse. Wenn ein optionaler Optimierungsbeweis fehlt, bleibt der kompatible Basispfad. Wenn dagegen die erforderliche Sprach-/Runtime-Semantik fehlt, wird die Konfiguration diagnostiziert. Weder ein Strategietag noch ein strukturell gültiges Modul ist bereits `codegenReady`.

## Gültige und ungültige Moduswahl

| Flow-Pässe | Speicher-Modus | Bedeutung |
| --- | --- | --- |
| off | language | Basispipeline mit vollständiger Sprachsicherheit und notwendigem Cleanup |
| on / auto | language | kompatible Optimierungen, bisheriger Runtime-/Provider-Vertrag |
| on / auto | hyperalloc-integration | vorhandenen GC erhalten; passenden Integration-Provider verlangen |
| on / auto | hyperalloc-managed | Flow-Provider explizit anfordern; erforderliche Semantik vollständig abdecken |
| off | hyperalloc-managed / hyperalloc-integration | widersprüchlich, Diagnose |

`auto` mit ausdrücklich gewähltem Flow-Speichermodus ist keine Erlaubnis, den Modus still zu ignorieren. Es gibt keinen automatischen GC-Wechsel. Diese Optionen sind Zielverträge; aktuell implementiert `SublangOptions` nur das Flow-Mode-Tag.

## 8. Effekt- und Alias-Provenance: vollständiger Call-Site-Kontext

```text
module @explain stage=High schema=planned revision=3 {
  require Core@planned, Object@planned, Memory@planned, GC@planned
  profile @host { unwind=none; finalizers=none; integers=signed_i64; gc=host }
  runtime @plugin_runtime {
    ownership=host_gc; roots=handles; errors=abort; moving=false
    apply_accepts_root_handle=true
    apply_may_retain_object=true; retained_object_is_gc_visible=true
  }
  provider @integration { runtime=@plugin_runtime; collector_replacement=false }
  class !Point { field x: !i64 immutable }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @apply_effects inherits=@unknown {
    mayThrow=false origin=Declared trusted=@plugin_runtime.apply
    mayAllocate=unknown origin=AssumedConservative
    escape.argument0=unknown origin=AssumedConservative
    reads=UnknownLocation origin=AssumedConservative
    writes=UnknownLocation origin=AssumedConservative
    synchronization=unknown origin=AssumedConservative
  }
  effects @main_effects inherits=@unknown {
    mayThrow=false origin=Proven analysis=@main_no_unwind revision=3
    mayAllocate=true origin=Proven analysis=@main_alloc revision=3
  }
  extern func @plugin.apply(borrow_read !root<!Point>) -> !i64
      profile=@host cc=provider effects=@apply_effects contract=@plugin_runtime.apply

  func @main() -> !i64 profile=@host effects=@main_effects {
    ^entry:
      %lexical = memory.scope.begin
      %roots = gc.root_scope.begin runtime=@plugin_runtime
      %point = gc.alloc_rooted !Point(x=i64(42)) roots=%roots scope_hint=%lexical
      %result = core.call.external @plugin.apply(%point)
                effects=@apply_effects contract=@plugin_runtime.apply
      gc.root_scope.end %roots
      memory.scope.end %lexical
      core.return %result
  }
}
pipeline { flow=on; memory=hyperalloc-integration; provider=@integration }
```

Der Provider kann eine entkommene Referenz GC-sichtbar erhalten. Der Call darf argument0 trotz Read-Zugriff behalten; das ursprüngliche Root-Handle selbst darf er nicht ungesichert speichern. `scope.end` und Root-Scope-Ende bedeuten keine Objektfreigabe. Das Modul ist deshalb ein konsistenter Basispfad für das unbekannte Escape.

```text
explain @local_blocked {
  code=FLOW-LOCAL-ESCAPE-UNKNOWN; severity=remark
  entity=(@explain, revision=3, @main, %point)
  requested=Local; effective=host_gc_heap
  related_alias=@point_unknown
  blocker={call=@plugin.apply; argument=0; fact=escape.argument0=unknown;
           origin=AssumedConservative; summary=@apply_effects}
  reason="Call kann das Objekt über die lokale Lebensdauer hinaus erhalten."
}
alias_fact @point_unknown {
  query=(location(@main,%point), UnknownLocation)
  answer=MayAlias; origin=AssumedConservative; revision=3
}
```

Entity, Modul und Revision stimmen zwischen IR und Bericht überein. Keine erfundene positive Provenance: Unknown bleibt Unknown. Ein ungeprüftes noescape-Attribut löst den Blocker nicht auf. Ohne einen passenden Heap-/Escape-Provider wäre die angeforderte Integration abzulehnen.

## 9. Exceptions mit Cleanup auf beiden Ausgängen

Eigenständiges schematisches Modul. Es zeigt die High-IR-Semantik; EH-/Resource-Operationen und deren Provider sind noch nicht implementiert.

```text
module @exception_cleanup stage=High schema=planned revision=1 {
  require Core@planned, Memory@planned, Exception@planned
  profile @resources {
    integers=signed_i64; unwind=exceptions; cleanup_order=reverse_acquisition
    cleanup_throw=forbidden
  }
  runtime @resources_rt {
    exception_abi=@target_eh
    exception_token=owned_rooted
    allocation_failure=abort
    drop_resource=nonthrowing
  }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @read_effects inherits=@unknown {
    mayThrow=true; mayAllocate=true; mayFail=true
    reads=runtime+argument0; writes=argument0
    escape.argument0=false
    origin=Declared trusted=@resources_rt.read
  }
  effects @drop_effects inherits=@unknown {
    mayThrow=false; mayAllocate=false; mayFail=false
    escape.argument0=false; reads=argument0; writes=runtime+argument0
    synchronization=none; observable=resource_close; mayDiverge=false
    origin=Declared trusted=@resources_rt.drop_resource
  }
  effects @load_effects inherits=@unknown {
    mayThrow=true; mayAllocate=true; mayFail=true
    origin=Proven analysis=@load_body revision=1
  }
  resource !Buffer provider=@resources_rt
  exception !Error provider=@resources_rt

  extern func @read(borrow_write !Buffer) -> !i64
      profile=@resources cc=provider contract=@resources_rt.read
      effects=@read_effects

  func @load() -> !i64 profile=@resources throws=!Error effects=@load_effects {
    ^entry:
      %buffer = memory.resource.acquire !Buffer failure=abort result=owned
      exception.invoke @read(%buffer) effects=@read_effects
          normal ^success(%result: !i64)
          unwind ^cleanup(%exception: owned_rooted !Error)
    ^success(%value: !i64):
      memory.resource.drop %buffer contract=@resources_rt.drop_resource effects=@drop_effects
      core.return %value
    ^cleanup(%pending: owned_rooted !Error):
      memory.resource.drop %buffer contract=@resources_rt.drop_resource effects=@drop_effects
      exception.resume %pending abi=@target_eh
  }
  func @loadOrZero() -> !i64 profile=@resources effects=@unknown throws=!Error {
    ^entry:
      exception.invoke @load() effects=@load_effects
          normal ^done(%result: !i64)
          unwind ^catch(%exception: owned_rooted !Error)
    ^done(%value: !i64):
      core.return %value
    ^catch(%pending: owned_rooted !Error):
      %matched = exception.matches %pending, !Error
      core.cond_branch %matched, ^handled, ^rethrow
    ^handled:
      exception.consume %pending runtime=@resources_rt
      core.return i64(0)
    ^rethrow:
      exception.resume %pending abi=@target_eh
  }
}
```

Die Resultat-/Exception-Namen an den Invoke-Kanten stehen für ausschließlich dort definierte Kantenergebnisse. `%buffer` dominiert beide Ausgänge. Der Provider bewahrt die rooted Exception über eventuelle Cleanup-Safepoints. Der normale Wert wird nicht auf dem Unwind-Pfad benutzt. Ein Throw während nonthrowing Cleanup verletzt hier den Vertrag; eine Sprache mit anderen Finally-Regeln braucht ein anderes Profil und Lowering.

Das Resource wird auf jedem relevanten Ausgang einmal gedroppt. Ein zusätzliches lexikalisches `scope.end` würde diese Prüfung nicht ersetzen. Bei weiteren Ausgängen (frühem Return, Catch, Break oder einem weiteren Throw) muss der CFG passende Cleanup-Pfade enthalten. Abort mit erforderlichem beobachtbarem Cleanup wäre ebenfalls ausdrücklich zu modellieren.

## 10. Pass- und Protokollberichte

```text
pass_result @local_attempt {
  pass=LocalPlacement
  input_snapshot=@explain:revision3
  output_snapshot=@explain:revision3
  changed=false
  requires={Object@planned; Memory@planned; effects; aliases; lifetime}
  invalidated=none
  preserved={effects; aliases; lifetime}
  verification={structure:valid; semantics:valid; memory_lifetime:valid}
  status=illustrative_expected_report
  evidence={effects_preserved:@effect_check; cleanup_preserved:@cleanup_check}
  decisions=[@local_blocked]
}
```

Dieser Passlauf auf Beispiel 8 verändert nichts, weil der einzige Local-Kandidat blockiert ist; Snapshot und Revision bleiben deshalb gleich. Ein tatsächlich mutierender Pass wie das Lowering in Beispiel 3 muss eine neue Revision samt Entity-Mapping liefern und abhängige Analysen invalidieren oder gültig übertragen. Der Verifier belegt hier die aufgeführten Invarianten, nicht automatisch volle Programm-Äquivalenz.

```text
client -> Hello {
  protocol_major=P; protocol_minor=M
  schemas=[S]
  required_extensions={Core:V; Dynamic:V; Memory:V; GC:V}
}
server -> Capabilities {
  protocol_major=P; selected_schema=S
  supported_extensions={Core:V; Dynamic:V; Memory:V; GC:V}
  targets=[@selected_target]; providers=[@integration]
}
client -> Submit {
  request_id=17
  snapshot=<module @dynamic from example 6, encoded under schema S>
  target=@selected_target; provider=@integration
  pipeline={flow=auto; memory=hyperalloc-integration}
}
server -> Result {
  request_id=17
  accepted_contract=<negotiated feature/profile/provider set>
  verification={structure:valid; semantics:not_checked; memory_lifetime:not_checked}
  codegenReady=false
  diagnostics=<structured records>
  explain=<optional decision records>
  artifacts=[]
  status=needs_remaining_verification
}
```

Ein konkreter abgelehnter Request erhält dieselbe strukturierte Diagnose wie die Textansicht:

```text
server -> Rejected {
  request_id=18
  code=Sublang-CAPABILITY-REQUIRED-UNSUPPORTED
  severity=error
  required={extension:Exception; version:V}
  available={extension:Exception; supported:false}
  entity=(@exception_cleanup, revision=1, @load, invoke@entry)
  source_span={source_id:1; start_line:12; start_column:3}
  stage=negotiation
  artifacts=[]
}
```

Die Snapshot-Identität umfasst Modul-ID, Revision, Funktions-ID und lokale Entity-ID. Eine Wire-Section referenziert diese IDs und speichert Konstanten beispielsweise als `f64 bits=0x8000000000000000` für -0, nicht als verlustbehafteten Dezimaltext. Diagnostik referenziert Source-IDs aus einer versionierten Source-Tabelle. Das Diagnosebeispiel ergänzt eine illustrative Source-/Entity-Zuordnung für den Request; es behauptet keine tatsächliche Zeile im Zielmodul.

Dies ist eine lesbare Protokollskizze, weder JSON-Wireformat noch feste Bytekodierung. P/M/S/V sind symbolisch; keine bereits veröffentlichte Versionsnummer. Fehlt eine erforderliche Dynamic-Extension, erfolgt eine Diagnose vor Optimierung. Das spätere Binärformat serialisiert keine nativen Zeiger oder internen Emerald-Objektlayouts.


## 11. Lexikalischer Scope endet, Objekt lebt weiter

```text
module @ownership_transfer stage=High schema=planned revision=1 {
  require Core@planned, Object@planned, Memory@planned
  profile @unique { unwind=none; finalizers=none; identity=observable }
  provider @unique_heap { ownership=unique; moving_gc=false; allocation_failure=abort }
  class !Box { field value: !i64 immutable }
  effects @unknown { default=unknown origin=AssumedConservative }
  effects @make_effects inherits=@unknown {
    mayAllocate=true; mayFail=true; mayThrow=false; escape.result=owned
    origin=Proven analysis=@make_body revision=1
  }
  func @make() -> owned !ref<!Box> profile=@unique effects=@make_effects {
    ^entry:
      %scope = memory.scope.begin
      %object = object.new !Box(value=i64(42)) result=owned
                provider=@unique_heap scope_hint=%scope
      %out = memory.move %object destination=return_owner
      memory.scope.end %scope
      core.return_owned %out
  }
  func @main() -> !i64 profile=@unique effects=@unknown {
    ^entry:
      %owned = core.call.direct @make() effects=@make_effects
      %answer = object.field.read %owned, !Box.value
      memory.drop %owned provider=@unique_heap
      core.return %answer
  }
}
```

Erwartetes Ergebnis 42. Der erste Scope endet vor dem letzten Objektzugriff. Das ist korrekt, weil Ownership zum Aufrufer transferiert wurde; eine Local-Platzierung im Stackframe von `@make` wäre falsch. Eine Rückgabe eines Borrows auf dasselbe lokale Objekt ohne gültigen Lifetime-Vertrag wäre dagegen abzulehnen. `memory.move` konsumiert `%object`; danach darf die alte Owner-Referenz nicht weiterverwendet werden.

## Abdeckung der Nutzeranforderungen

| Anforderung | Konkretes Beispiel |
| --- | --- |
| Erstklassige Effekte, globale Reads/Writes, Synchronisation | Summaries in 1–9; UnknownLocation und Synchronisation in 8 |
| Declared / AssumedConservative / Proven | einheitliche Notation, 2 und 8 |
| Scope unabhängig von Lifetime/Ownership | Plan in 3, GC-Escape in 8, Transfer in 11 |
| Fehleraktion, Unwinding, Cleanup, Catch, Rethrow | 1/3 und 9 |
| Schema, Features, stabile IDs, Diagnosen, öffentliche Grenze | 10 und `Sublang_IR_Contracts.md`; kein natives Objektlayout als Wire-ABI |
| Struktur / Semantik / Memory separat, Revision/Invalidierung | Plan in 3, Pass- und Result-Bericht in 10 |
| Gemeinsame Effect-/Alias-Abstraktion | 3 und 8 |
| Explain nennt blockierenden Call und Alias-Fakt | 8 |
| Dynamische Typen, Heap-Referenzen und Runtime-Fallback | 6 |

Alle positiven Prüfberichte und Analysebeweise der Zielbeispiele sind **illustrative erwartete Resultate**. Nur die getrennten schema=1-Builder-Dumps besitzen den früher dokumentierten tatsächlichen Strukturprüflauf. Für diese Überarbeitung wurde kein Compiler gestartet.
