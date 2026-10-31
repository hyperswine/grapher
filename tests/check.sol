#!/usr/bin/env sol
# Native feature tests, exact reference plotChecks and expected compiler refusals.
S = use "support".
J = use "sol/lib/json".
P = use "sol/lib/proc".

reference points = Str.join "\n" (List.map (fn row -> y = 10 - row;
  Str.join "" (List.map (fn x ->
    if List.any (fn p -> p == (x,y)) points then "*"
    else if x == 0 and y == 0 then "+" else if x == 0 then "|"
    else if y == 0 then "-" else " ") (List.range -20 20))) (List.range 0 20)).

plotCase index points =
  args = List.map (fn p -> (x,y) = p; "{x},{y}") points;
  output = S.command (["./build/grapher", "plot"] + args) 0;
  newline = Str.find 10 output;
  _ = S.check "plot header absent" (newline >= 0);
  header = Str.slice output 0 newline;
  chart = Str.slice output (newline + 1) (Str.len output);
  _ = S.check "wrong point count in {header}" (Str.contains "{List.len points} I32 points" header);
  _ = S.check "ASCII plot differs from independent reference: case {index}" (chart == "{reference points}\n");
  S.passed "ASCII plot matches independent reference: case {index}".

badPoint token =
  output = S.command ["./build/grapher", "plot", token] 2;
  _ = S.check "missing invalid-point diagnostic" (Str.contains "grapher:" output);
  S.passed "CLI rejects malformed/out-of-range point: {token}".

negatives = [
  ("mixed_i32", ["I32"]),
  ("vector_element", ["type","Vector","Int","String"]),
  ("vector_reuse", ["linear","owned","consum","more than once","twice"]),
  ("generic_duplicate", ["duplicate","owned","unrestricted"]),
  ("linear_discard", ["linear","owned","discard","consum"]),
  ("invalid_type_path", ["missing","path","field"]),
  ("nonexhaustive", ["exhaustive","Second","coverage"]),
  ("nondecreasing_measure", ["measure","decreas","count"]),
  ("resource_bound", ["COST","OVER","bound"]),
  ("missing_struct_method", ["missing","conform","(+)","Add"]),
  ("wrong_signature", ["type","Int","String"]),
  ("unmeasured_recursion", ["unsafe","recurs","measure"])].

negative scratch item =
  (name, words) = item;
  ProcessResult code stdout stderr = S.observed
    ["fpr","compile","--system=posix","--check-only","tests/negative/{name}.fpr","{scratch}/{name}.s"];
  output = "{stdout}{stderr}";
  _ = S.writeText "evidence/negative-{name}.log" output;
  _ = S.check "invalid program accepted: {name}" (code != 0);
  _ = S.check "negative test had a syntax error: {name}\n{output}"
    (not (S.hasAny ["does not parse","unexpected"] output));
  _ = S.check "wrong diagnostic for {name}\n{output}" (S.hasAny words output);
  S.passed "compiler refuses {name}".

runChecks u =
  _ = S.ensureRoot Unit;
  _ = S.command ["/bin/mkdir","-p","evidence"] 0;
  # Remove any earlier successful report before starting a fresh run.
  _ = S.command ["/bin/rm","-f","evidence/cli-results.json"] 0;
  runtime = S.command ["./build/grapher","test"] 0;
  _ = S.writeText "evidence/cli-runtime.log" runtime;
  _ = S.need (IO.stdoutText runtime);
  _ = S.check "native checks did not complete" (Str.contains "25 runtime checks passed" runtime);
  first = S.passed "25 native runtime language checks";
  fixtures = [[],[(0,0)],[(-20,10),(20,-10),(1,1)],
    [(0,0),(0,0),(2147483647,-2147483648),(-21,11)]];
  plotChecks = List.map (fn item -> (index,points) = item; plotCase index points)
    (List.zip (List.range 1 4) fixtures);
  invalid = List.map badPoint ["bad","1,2,3","1,","4294967296,0"];
  _ = S.check "unknown command lacks usage" (Str.contains "usage:" (S.command ["./build/grapher","unknown"] 2));
  unknown = S.passed "unknown command exits 2";
  scratch = tempDir "grapher-negative-sol";
  refused = List.map (negative scratch) negatives;
  root = S.need (IO.cwd Unit);
  build = P.withEnv "XDG_CACHE_HOME" "{root}/.cache"
    (S.spec ["fpr","build","tests/runtime/contract_violation.fpr","-o","build/contract-violation"]);
  _ = S.need (P.output (Proc.runNow build));
  violation = S.command ["./build/contract-violation"] 1;
  _ = S.check "refinement failure lacks expected diagnostic"
    (Str.contains "precondition violated" violation and Str.contains "n > 0" violation);
  _ = S.writeText "evidence/contract-violation.log" violation;
  contract = S.passed "runtime refuses a violated refinement contract";
  compiler = Str.trim (S.command ["fpr","--version"] 0);
  checks = [first] + plotChecks + invalid + [unknown] + refused + [contract];
  _ = S.report "evidence/cli-results.json" (J.JObj [
    ("runtimeChecks",J.JNum 25), ("negativeCompilerChecks",J.JNum (List.len negatives)),
    ("runtimeRefusals",J.JNum 1), ("cliIntegrationChecks",J.JNum 9),
    ("compiler",J.JStr compiler), ("runner",J.JStr "Sol"),
    ("sourceCheckoutsPresent",J.JBool (exists "../fprisc" or exists "../qos")),
    ("passed",J.JBool True),
    ("checks",J.JArr (List.map (fn name -> J.JObj [("name",J.JStr name),("passed",J.JBool True)]) checks))]);
  print "PASS: 25 runtime, 12 compiler refusal, 1 runtime contract refusal, 9 CLI integration checks (Sol)".

> runChecks Unit.
