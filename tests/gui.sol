#!/usr/bin/env sol
# Sol owns the QOS process group. A panic/abort/Ctrl-C sweeps its ProcessJob.
# The shell only connects descriptors; all test sequencing and assertions live
# here. Exact evdev records are emitted as Bytes through a bounded pipeline.
S = use "support".
P = use "sol/lib/proc".
J = use "sol/lib/json".
Frames = use "framecore".

waitLine : String -> String -> Int -> (tries : Int | measure tries) -> Int .
waitLine log needle offset tries | tries <= 0 = error "timeout waiting for {needle}; see {log}".
waitLine log needle offset tries =
  text = readNow log;
  _ = S.check "desktop failure; see {log}" (not (S.hasAny
    ["PANIC","SIGSEGV","app forced stop","Application unavailable"] text));
  if Str.contains needle (Str.slice text offset (Str.len text)) then
    _ = print needle; Str.len text
  else _ = sleepMs 100; waitLine log needle offset (tries - 1).

event code value = S.need (Bytes.fromList
  (List.map (fn n -> 0) (List.range 1 16) + [1,0,code%256,Num.floor (code/256.0),value,0,0,0])).
key fifo code =
  bytes = Bytes.concat [event code 1,event code 0];
  stage = P.spec ["/bin/sh","-c","cat > \"$1\"","grapher-key",fifo];
  PipelineResult code statuses stdout stderr = S.need (Proc.pipeline
    (PipelineSpec [stage] (PipeBytes bytes) (PipeCapture 1024) (PipeCapture 4096) 5000 PipeFail));
  _ = S.check "failed to deliver key event" (code == 0 and statuses == [0]);
  sleepMs 300.

waitCapture : String -> (tries : Int | measure tries) -> Bytes .
waitCapture path tries | tries <= 0 = error "incomplete snapshot {path}".
waitCapture path tries = case S.tryReadBytes path of
    Ok bytes -> if Bytes.len bytes == 16 + 1280*720*3 then bytes
      else _ = sleepMs 100; waitCapture path (tries - 1)
  | Err why -> _ = sleepMs 100; waitCapture path (tries - 1).

shot root fifo log offset number name =
  source = "/private/tmp/qos-shell-{number}.ppm";
  ProcessResult present out err = S.observed ["/bin/test","-e",source];
  _ = S.check "existing snapshot: {source}" (present == 1);
  _ = key fifo 4025;
  next = waitLine log "shell: snapshot {number}" offset 300;
  bytes = waitCapture source 100;
  dest = "{root}/evidence/grapher-{name}.ppm";
  _ = S.need (Fs.renameNow source dest True);
  _ = S.command ["/usr/bin/sips","-s","format","png",dest,
    "--out","{root}/evidence/grapher-{name}.png"] 0;
  (next,bytes).

awaitExit : ProcessJob -> (tries : Int | measure tries) -> Unit .
awaitExit job tries =
  (status,next) = Proc.poll job;
  if S.need status then
    PipelineResult code statuses stdout stderr = S.need (Proc.wait next);
    S.check "QOS did not exit cleanly: {code}/{statuses}" (code == 0 and statuses == [0])
  else if tries <= 0 then
    _ = S.need (Proc.cancel next); error "desktop shutdown timed out"
  else _ = sleepMs 100; awaitExit next (tries - 1).

exercise root fifo log job =
  offset0 = waitLine log "shell: Main Profile ready" 0 300;
  _ = key fifo 107;
  _ = key fifo 28;
  offset1 = waitLine log "shell: open grapher" offset0 300;
  _ = sleepMs 800;
  (offset2,initial) = shot root fifo log offset1 1 "parabola";
  first = S.passed "desktop launched installed Grapher and captured parabola";
  _ = key fifo 3;
  offset3 = waitLine log "grapher: dataset Triangle wave" offset2 300;
  (offset4,wave) = shot root fifo log offset3 2 "wave";
  _ = S.check "dataset switch did not change rendering" (wave != initial);
  second = S.passed "dataset switching changes the rendered frame";
  _ = key fifo 46;
  offset5 = waitLine log "grapher: clear; 0 points" offset4 300;
  (offset6,empty) = shot root fifo log offset5 3 "empty";
  _ = key fifo 106;
  _ = key fifo 103;
  _ = key fifo 28;
  offset7 = waitLine log "grapher: add (1,1); 1 points" offset6 300;
  (offset8,custom) = shot root fifo log offset7 4 "custom";
  _ = S.check "custom point did not change rendering" (custom != empty);
  third = S.passed "clear, arrow cursor movement and Enter add a custom I32 point";
  _ = key fifo 28;
  offset9 = waitLine log "grapher: add (1,1); 1 points" offset8 300;
  fourth = S.passed "adding the same point does not duplicate it";
  _ = key fifo 14;
  offset10 = waitLine log "grapher: remove; 0 points" offset9 300;
  fifth = S.passed "Backspace removes the last point";
  _ = key fifo 34;
  offset11 = waitLine log "grapher: grid False" offset10 300;
  (offset12,noGrid) = shot root fifo log offset11 5 "no-grid";
  _ = S.check "grid toggle did not change rendering" (noGrid != empty);
  sixth = S.passed "grid toggle changes rendering";
  _ = key fifo 4;
  offset13 = waitLine log "grapher: dataset Constellation" offset12 300;
  (offset14,stars) = shot root fifo log offset13 6 "stars";
  _ = key fifo 19;
  offset15 = waitLine log "grapher: dataset Constellation" offset14 300;
  seventh = S.passed "third dataset and reset work";
  _ = key fifo 1;
  offset16 = waitLine log "shell: home" offset15 300;
  _ = key fifo 16;
  _ = awaitExit job 200;
  _ = S.check "desktop cleanup failed; see {log}"
    (not (S.hasAny ["PANIC","SIGSEGV","app forced stop","shutdown failed","cleanup unconfirmed"] (readNow log)));
  eighth = S.passed "Escape returns home; desktop shuts down cleanly";
  [first,second,third,fourth,fifth,sixth,seventh,eighth].

runGui u =
  _ = S.ensureRoot Unit;
  _ = S.command ["/bin/mkdir","-p","evidence"] 0;
  _ = S.command ["/bin/rm","-f","evidence/desktop-results.json","evidence/frame-results.json"] 0;
  _ = List.map (fn name -> S.need (Env.unset name))
    ["FPR_HOME","FPR_PATH","FPR_FOREIGN","FPRISC_ROOT","FPR_DISK","FPR_DISK_LOCK_FD","FPR_EVDEV"];
  root = S.need (IO.cwd Unit);
  scratch = tempDir "grapher-gui-sol";
  disk = "{scratch}/main.disk";
  fifo = "{scratch}/keys.evd";
  log = "{root}/evidence/desktop.log";
  _ = print (S.command ["qos","disk","create",disk] 0);
  _ = print (S.command ["qos","install","{root}/desktop/build/grapher.qa",disk] 0);
  _ = S.command ["/usr/bin/mkfifo",fifo] 0;
  # Holding descriptor 3 read/write avoids FIFO writer-open races. It is
  # inherited inside the owned process group and closes with that group.
  stage = P.withEnv "FPR_PORT" "0" (P.withEnv "FPR_EVDEV" fifo (P.inDir scratch (P.spec ["/bin/sh","-c",
    "exec > \"$2\" 2>&1; exec 3<> \"$1\"; exec qos run \"$3\"",
    "grapher-desktop",fifo,log,disk])));
  job = S.need (Proc.start (PipelineSpec [stage] (PipeBytes (Bytes.empty Unit))
    (PipeCapture 1024) (PipeCapture 4096) 180000 PipeFail));
  # The log is created by the child; give it a bounded chance to appear.
  _ = sleepMs 300;
  checks = exercise root fifo log job;
  _ = Frames.run Unit;
  _ = S.report "evidence/desktop-results.json" (J.JObj [
    ("passed",J.JBool True), ("sdk",J.JStr "QOS Portable 0.2.0"), ("runner",J.JStr "Sol"),
    ("checks",J.JArr (List.map J.JStr checks)),
    ("captures",J.JArr (List.map (fn name -> J.JStr "grapher-{name}.png")
      ["parabola","wave","empty","custom","no-grid","stars"]))]);
  print "PASS: 8 graphical workflow checks and 6 rendered-frame checks (Sol)".

> runGui Unit.
