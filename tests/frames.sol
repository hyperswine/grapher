#!/usr/bin/env sol
S = use "support".
Frames = use "framecore".
> _ = S.ensureRoot Unit;
  _ = S.command ["/bin/rm","-f","evidence/frame-results.json"] 0;
  Frames.run Unit.
