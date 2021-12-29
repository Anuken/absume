import ecs, fau/presets/[basic, effects], fau/util/util, math

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas")

const 
  scl = 4f
  playerSpeed = 60f

var player: EntityRef

defineEffects:
  bubble(lifetime = 1f):
    let off = vec2(0f, e.fin.powout(3f) * 4f)
    poly(e.pos + off, 10, 4f + 4f * e.fin.pow(4f), stroke = 2f * e.fout)
    fillCircle(e.pos + vec2(1.1f) + off, 2f * e.fout)

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, rot: float32
      bub: float32
    
    Player = object

makeTimedSystem()

sys("move", [Player, Vel, Pos]):
  all:
    let vec = vec2(axis(keyA, keyD), axis(keyS, keyW)).lim(1f) * playerSpeed * fau.delta
    if vec.len > 0:
      item.vel.rot = aapproach(item.vel.rot, vec.angle, 3f * fau.delta)
    
    let base = vec.angled(item.vel.rot)

    item.pos.x += base.x
    item.pos.y += base.y

    if vec.len > 0:
      incTimer(item.vel.bub, 7f / 60f):
        effectBubble(item.pos.vec2 + randVec(7f))

    #if item.vel.bub >= 1f:
    #  effectBubble(item.pos.vec2 + randVec(5f))
    #  item.vel.bub = 0f

sys("draw", [Main]):
  fields:
    buffer: Framebuffer

  init:
    player = newEntityWith(Vel(), Pos(), Player())
    sys.buffer = newFramebuffer()

  start:
    if keyEscape.tapped: quitApp()

    sys.buffer.clear(colorBlack)
    sys.buffer.resize(fau.sizei div scl.int)
    
    fau.cam.update(fau.size / scl)
    fau.cam.use()

    drawBuffer(sys.buffer)
  
  finish:
    discard

sys("drawPlayer", [Player, Pos, Vel]):
  all:
    draw("player".patch, item.pos.vec2, rotation = item.vel.rot - 90f.rad)

makeEffectsSystem()

sys("endDraw", [Main]):
  start:
    drawBufferScreen()
    sysDraw.buffer.blit()

launchFau("New Year's Jam 2021")
