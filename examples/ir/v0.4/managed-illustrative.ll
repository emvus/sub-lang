; Illustrative LLVM output; not assembled in this documentation task.
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
