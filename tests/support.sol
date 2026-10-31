# Shared immediate I/O: test processes observe fresh files and never run ahead
# of queued transaction writes. argv always remains a structured list.
P = use "sol/lib/proc".
J = use "sol/lib/json".

need result = case result of Ok x -> x | Err why -> error "{why}".
check message condition = if condition then Unit else error message.
passed name = _ = print "PASS  {name}"; name.

ensureRoot u = check "run from Grapher's project directory" (exists "cli/main.fpr").
spec argv = P.withTimeout 90000 (P.spec argv).
observed argv = need (Proc.runNow (spec argv)).
command argv expected =
  ProcessResult code stdout stderr = observed argv;
  _ = check "{argv}: expected exit {expected}, got {code}\n{stdout}{stderr}" (code == expected);
  "{stdout}{stderr}".

writeText path text =
  result = Proc.runNow (P.withStdin text (spec ["/bin/sh", "-c", "cat > \"$1\"", "grapher-write", path]));
  _ = need (P.output result);
  Unit.

report path value = writeText path "{J.pretty value}\n".
hasAny words text = List.any (fn word -> Str.contains (Str.lower word) (Str.lower text)) words.

tryReadBytes path = case Stream.openRead path 65536 of
    Err why -> Err why
  | Ok reader ->
      (result, reader2) = Stream.foldChunks (fn chunks bytes -> bytes :: chunks) [] reader;
      closed = Stream.closeRead reader2;
      case closed of
        Err why -> Err why
      | Ok u -> mapOk (fn chunks -> Bytes.concat (List.rev chunks)) result.
readBytes path = need (tryReadBytes path).
