# Archived extended Sublang IR examples

> Archived on October 10, 2026. Foreign collector integration is outside active scope; see the archive README.

**Status: proposed notation, not executable .sublang programs.**

These archived examples illustrate the earlier v0.4 collector-integration proposal. They are historical requirements, not implemented public operations or active roadmap items. Their code blocks are preserved while explanatory prose is translated.

Each numbered module is an independent design example. Reports refer to their named modules; symbolic target/runtime contracts are explicit dependencies. !T denotes a type, %x a function-local SSA value, ^b a block and @name a module definition. Block arguments serve as phi nodes. Declarations such as runtime/provider/profile are explanatory contract notation, not an established grammar. Record fields will be versioned during implementation.

### Common v0.4 notation

effects @unknown { default=unknown origin=AssumedConservative } conservatively makes every unspecified effect unknown. Specialized summaries override only explicit facts. Declared/trusted identifies a bound provider/profile contract; Proven/analysis/revision illustrates a same-snapshot analysis result. These proposed proofs have not been executed by Sublang.

Every function/call references a summary. Effectful builtins use explicit versioned opcode contracts from required extensions; missing contracts produce diagnostics. reads/writes=local(...) remains an actual memory effect. No global writes does not mean no writes.

The individual historical collector examples are preserved elsewhere in this archive. This notation is a design proposal, not a published input grammar.

## 1. Procedural language without Flow: checked i64

The frontend may implement a C-like, functional or other language. This profile explicitly selects checked i64 and abort rather than inheriting unspecified source-language behavior. Wrapping arithmetic, exceptions or other rules require appropriate contracts.

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

Result: 42. A potentially failing call cannot simply disappear when its result is unused. This i64 profile produces 4_000_000_000 for 2_000_000_000 + 2_000_000_000; out-of-range results follow the failure contract. Flow off does not disable semantics or required safety checks.

## 2. OO identity and virtual dispatch

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

The interface contract forbids unwinding; other effects remain unknown. Unknown implementations block unproved devirtualization/escape transformations. A borrowed receiver does not imply no allocation/global mutation. Direct-call replacement needs a complete target set or valid guard/fallback. Dynamic object identity remains observable.

## 3. Managed Flow: temporary object through planning to LLVM

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

Identity is never observed here. Folded may eliminate the object if effects also permit it. Folded is deliberately disabled for this Local demonstration. Placement is a pass decision, not a source-language promise.

### Schematic memory plan

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

The plan relies on separate ownership/lifetime analyses. scope_hint is only a candidate; scope.end alone justifies neither drop nor stack placement. Verdicts shown here are expected design reports.

The 16 bytes here are two fields, not an object header. This layout is valid only for this target/plan. FFI/reflection would add constraints. Revision, target and provider determine validity; another revision cannot reuse the plan unchecked.

### Schematic Low IR

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

Lowering consumes the High plan at revision 7 and produces revision 8. Low verification checks entity remapping and layout. LLVM emission cannot invent a conflicting Point layout.

### Concrete LLVM illustration

This illustrates the selected 64-bit target and abort contract. It was not assembled as part of this documentation change. The backend defines the supported LLVM version/data layout.

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

LLVM can reduce this to ret i64 42. That is general optimization, not a benchmark-specific rule. nsw alone would not implement the required failure path.

## 4. Flow Integration with an existing moving GC

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

gc.alloc_rooted is a proposed provider operation: allocation and handle publication are GC-safe; initialization sets the Ref field to null. Barriers take handles and resolve current addresses. Reload references from relocated roots after safepoints; do not reuse stale raw pointers. No further safepoint occurs between these loads and the final field access.

Result: 1. Root-scope cleanup releases handles, not the collector-owned heap objects. Reject the mode without compatible root/barrier contracts. Flow may apply compatible optimizations but cannot silently replace the collector.

## 5. Managed sharing and cycles: Bond

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

Edges update sharing/cycle metadata. Release removes an external owner while internal edges initially remain. The provider must reclaim unreachable cycles; immediate collection is not asserted. Observable finalizers, weak refs or threads require stronger contracts and cannot be silently discarded.

## 6. Dynamic language: tags, moving heap and runtime fallback

This mini-language permits i64, f64 and immutable strings. Addition performs numeric promotion or string concatenation. Integer overflow falls back to the runtime and returns f64 here; other combinations abort. These are explicit mini-language rules, not implicit Python/JavaScript semantics.

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

Expected result: 11. The runtime receives handles rather than stale heap pointers. Results enter a root scope before another safepoint; adopt_owned does not allocate. The fast path also returns an owned handle. Byte-length access and root cleanup do not safepoint here. Two raw dynamic parameters would not satisfy this moving-GC contract.

add_effects conservatively bounds the whole call: a numeric fast path may not allocate, but string paths can allocate/mutate runtime state. Runtime aliases remain MayAlias absent proof. Unsupported moving providers fail rather than reuse obsolete addresses. No JIT is required.

## 7. Closure capture lifetime

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

Result: 42. The capture is an independent value, not a borrow of an expired stack local. Escaping borrowed captures require a lifetime proof, a semantically valid representation or rejection. Automatic copying is not generally correct with observable identity/mutation.

## All eight Flow strategies in IR

High IR expresses logical objects and language rules. Placement belongs to analysis/memory plans; frontends do not need eight allocation opcodes.

| Strategy | Logical example | Physical implementation with valid proof |
| --- | --- | --- |
| Folded | Temporary Point, fields only | Scalar values, no object allocation |
| Inline | Value list with unobservable identity | Direct buffer elements, planned stride/layout |
| Local | Nonescaping scoped object | Stack slot, lifetime markers and required cleanup |
| Pool | Repeated complete lifetimes | Reuse after every prior reference expires |
| Shard | Group with compatible lifetime | Region, required drops, then bulk release |
| Root | Exclusive transferable owner | Transfer and exactly-once cleanup on relevant paths |
| Bond | Shared graph/cycles | Compatible sharing/cycle runtime and tracked edges |
| Static | Eligible immutable data/literals | Globals preserving identity/interning semantics |

### Example mixed plan

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

Proof references are placeholders for actual versioned results. Missing optional optimization proofs preserve a compatible baseline. Missing required language/runtime semantics produce diagnostics. A strategy label or structural validity alone does not imply codegen readiness.

## Valid and invalid mode selection

| Flow passes | Memory mode | Meaning |
| --- | --- | --- |
| off | language | Baseline preserves language safety and required cleanup |
| on / auto | language | Compatible optimization under the existing provider contract |
| on / auto | hyperalloc-integration | Keep the existing GC and require a compatible integration provider |
| on / auto | hyperalloc-managed | Explicit Flow provider with complete required semantics |
| off | hyperalloc-managed / hyperalloc-integration | Contradictory proposed configuration; diagnose |

Auto never authorizes silently ignoring an explicitly required memory provider or switching collectors. These are historical proposed options, not an implemented CLI.

## 8. Effect and alias provenance: complete call-site context

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

The provider can preserve escaping references visibly to the collector. Read access does not prevent retaining argument0, but the original root handle cannot be stored without protection. Lexical/root scope ends do not imply object deallocation. This is the proposed conservative baseline for unknown escape.

```text
explain @local_blocked {
  code=FLOW-LOCAL-ESCAPE-UNKNOWN; severity=remark
  entity=(@explain, revision=3, @main, %point)
  requested=Local; effective=host_gc_heap
  related_alias=@point_unknown
  blocker={call=@plugin.apply; argument=0; fact=escape.argument0=unknown;
           origin=AssumedConservative; summary=@apply_effects}
  reason="The call may retain the object beyond its local lifetime."
}
alias_fact @point_unknown {
  query=(location(@main,%point), UnknownLocation)
  answer=MayAlias; origin=AssumedConservative; revision=3
}
```

Entity/module/revision match between IR and report. Unknown remains unknown; an unchecked noescape hint does not resolve the blocker. Without a compatible escape/heap provider the requested integration must fail.

## 9. Exceptions with cleanup on both exits

Independent schematic module illustrating High-IR semantics. These EH/resource operations and providers are not implemented.

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

Invoke edge names denote results defined only on their corresponding edges. Buffer dominates both exits. The provider preserves the owned exception across cleanup. The normal result is not used on unwind. Throwing from nonthrowing cleanup violates this contract; other finally semantics need another profile/lowering.

The resource is dropped once on every required exit. Another lexical scope.end would not prove this. Early return/catch/break/additional throw need matching cleanup paths. Required observable cleanup before abort must also be explicit.

## 10. Pass and protocol reports

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

This pass changes nothing because the only Local candidate is blocked, so snapshot/revision remain unchanged. Actual transformations, such as section 3 lowering, need new revisions/entity mappings and analysis invalidation/preservation. Verification proves listed invariants, not arbitrary program equivalence.

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

A rejected request receives the same structured diagnosis as the text view:

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

Snapshot identity includes module/revision/function/local entity. Wire records reference those IDs and preserve raw constants, e.g. negative-zero bits rather than lossy decimal float formatting. Diagnostics reference a versioned source table. The illustrated source/entity mapping does not assert an actual source line in a target module.

This is a readable protocol sketch, not JSON wire encoding or fixed bytes. P/M/S/V are symbolic, not published versions. Missing required extensions fail before optimization. Serialization must not expose process pointers or Emerald object layouts.


## 11. Scope ends while the object survives

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

Expected result: 42. Ownership has transferred before the original scope ends, so placing the object in make's stack frame would be incorrect. Returning a borrow without a lifetime contract must fail. memory.move consumes object; the prior owner cannot be reused.

## Requirement coverage

| Requirement | Example |
| --- | --- |
| First-class effects, globals and synchronization | Summaries in 1–9; UnknownLocation/synchronization in 8 |
| Declared / AssumedConservative / Proven | Common notation, 2 and 8 |
| Scope distinct from lifetime/ownership | Plan 3, GC escape 8, transfer 11 |
| Failure, unwind, cleanup, catch and rethrow | 1/3 and 9 |
| Schema/features/stable IDs/diagnostics/public boundary | 10 and IR Contracts; no native layouts as Wire ABI |
| Separate validation and revision invalidation | Plan 3 and reports 10 |
| Shared effect/alias abstraction | 3 and 8 |
| Explain identifies blocking call/alias | 8 |
| Dynamic types, heap values and fallback | 6 |

All positive analysis/validation reports in these architecture examples are illustrative expected results. Historical core dumps have separate structural-check evidence; executable native examples have their own bounded backend evidence. No compiler was run for this documentation translation.
