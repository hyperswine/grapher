# Binary PPM validation, scanline connected components, independent fixtures.
# Only one cropped scanline is converted to octets at a time. Components may
# split or merge: prior spans are retained until the complete row is joined.
S = use "support".
J = use "sol/lib/json".
Run = {lo : Int, hi : Int, sx : Int, sy : Int, n : Int}.
Component = {prior : List (Int,Int), current : List (Int,Int), sx : Int, sy : Int, n : Int}.

flushRun start finish sx n y acc = if n == 0 then acc
  else {lo=start, hi=finish, sx=sx, sy=y*n, n=n} :: acc.
runs : (pixels : List Int | measure pixels) -> Int -> Int -> Int -> Int -> Int -> List Run -> List Run .
runs pixels x y start sx n acc = case pixels of
    [] -> List.rev (flushRun start (x - 1) sx n y acc)
  | r :: g :: b :: rest ->
      if g > 160 and b > 110 and g - r > 80 then
        runs rest (x + 1) y (if n == 0 then x else start) (sx + x) (n + 1) acc
      else runs rest (x + 1) y 0 0 0 (flushRun start (x - 1) sx n y acc)
  | other -> error "incomplete RGB pixel".

overlap run comp = List.any (fn span -> (lo,hi) = span;
  lo <= run.hi and hi >= run.lo) comp.prior.
merge a b = {prior=List.concat [a.prior,b.prior], current=List.concat [a.current,b.current],
  sx=a.sx+b.sx, sy=a.sy+b.sy, n=a.n+b.n}.
joinRun groups run =
  joined = List.filter (overlap run) groups;
  rest = List.filter (fn c -> not (overlap run c)) groups;
  seed = {prior=[], current=[(run.lo,run.hi)], sx=run.sx, sy=run.sy, n=run.n};
  List.fold merge seed joined :: rest.
center c = (c.sx * 1.0 / c.n, c.sy * 1.0 / c.n).
centers groups = List.map center (List.filter (fn c -> c.n > 8) groups).

scan : Bytes -> (row : Int | measure (541 - row)) -> Int -> List Component -> List (Int,Int) -> List (Int,Int) .
scan bytes row header active done | row > 540 = done + centers active.
scan bytes row header active done =
  strip = S.need (Bytes.slice (header + (row*1280+64)*3) (910*3) bytes);
  groups = List.fold joinRun active (runs (Bytes.toList strip) 64 row 0 0 0 []);
  finished = List.filter (fn c -> c.current == []) groups;
  continuing = List.filter (fn c -> c.current != []) groups;
  fresh = List.map (fn c -> {c | prior=c.current, current=[]}) continuing;
  scan bytes (row + 1) header fresh (done + centers finished).

dots name =
  bytes = S.readBytes "evidence/grapher-{name}.ppm";
  expected = S.need (Utf8.encode "P6\n1280 720\n255\n");
  header = Bytes.len expected;
  _ = S.check "{name}: wrong PPM header/resolution"
    (S.need (Bytes.slice 0 header bytes) == expected);
  _ = S.check "{name}: incomplete PPM payload" (Bytes.len bytes == header + 1280*720*3);
  scan bytes 119 header [] [].

fixtures = [
  ("parabola",List.map (fn n -> x=n*2; (x,Num.floor (x*x/20.0) - 10)) (List.range -10 10)),
  ("wave",List.map (fn n -> x=n*2; (x,10 - Numeric.abs ((x + 20) % 20 - 10)*2)) (List.range -10 10)),
  ("empty",[]), ("custom",[(1,1)]), ("no-grid",[]),
  ("stars",[(-17,5),(-12,-4),(-8,7),(-3,1),(2,-7),(5,6),(9,-2),(13,8),(18,-5)])].

verify calibration item =
  (left,top,sx,sy) = calibration;
  (name,points) = item;
  actual = dots name;
  _ = S.check "{name}: wrong point count, got {List.len actual}, expected {List.len points}"
    (List.len actual == List.len points);
  _ = List.map (fn p -> (x,y)=p; px=left+(x + 20)*sx; py=top+(10 - y)*sy;
    S.check "{name}: missing rendered point ({x},{y})"
      (List.any (fn q -> (ax,ay)=q; Numeric.abs (ax - px) <= 3 and Numeric.abs (ay - py) <= 3) actual)) points;
  _ = S.passed "rendered {name}: {List.len points} points at the expected graph coordinates";
  (name,J.JNum (List.len points)).

run u =
  initial = dots "parabola";
  _ = S.check "parabola: expected 21 dots" (List.len initial == 21);
  xs = List.map (fn p -> (x,y)=p; x) initial;
  ys = List.map (fn p -> (x,y)=p; y) initial;
  left = List.fold Numeric.min 1280 xs;
  right = List.fold Numeric.max 0 xs;
  top = List.fold Numeric.min 720 ys;
  bottom = List.fold Numeric.max 0 ys;
  rows = List.map (verify (left,top,(right - left)/40.0,(bottom - top)/20.0)) fixtures;
  S.report "evidence/frame-results.json" (J.JObj [
    ("passed",J.JBool True), ("runner",J.JStr "Sol"), ("frames",J.JObj rows),
    ("method",J.JStr "scanline connected components inside chart; independent coordinate fixtures; 3px tolerance"),
    ("captureResolution",J.JArr [J.JNum 1280,J.JNum 720])]).
