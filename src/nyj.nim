import ecs, fau/presets/[basic, effects], fau/util/util, math, random

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas")

#palette
const
  col1 = %"2c2352"
  col2 = %"4f6b7a"
  col3 = %"a7c6c5"

const 
  scl = 4f
  playerSpeed = 60f

var player: EntityRef

defineEffects:
  bubble(lifetime = 1f):
    let off = vec2(0f, e.fin.powout(3f) * 7f)
    poly(e.pos + off, 10, 4f + 4f * e.fin.pow(4f), stroke = 2f * e.fout, color = col3)
    fillCircle(e.pos + vec2(1.1f) + off, 2f * e.fout, color = col3)

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, rot: float32
      bub: float32
      moveTime: float32
    
    Player = object

makeTimedSystem()

sys("move", [Player, Vel, Pos]):
  all:
    let vec = vec2(axis(keyA, keyD), axis(keyS, keyW)).lim(1f) * playerSpeed * fau.delta
    if vec.len > 0:
      item.vel.rot = aapproach(item.vel.rot, vec.angle, 6f * fau.delta)
    
    let base = vec.angled(item.vel.rot)

    item.pos.x += base.x
    item.pos.y += base.y

    if vec.len > 0:
      item.vel.moveTime += fau.delta
      incTimer(item.vel.bub, 3f / 60f):
        effectBubble(item.pos.vec2 + vec2l(item.vel.rot, 11f) + randVec(7f))

sys("draw", [Main]):
  fields:
    buffer: Framebuffer

  init:
    player = newEntityWith(Vel(), Pos(), Player())
    sys.buffer = newFramebuffer()

  start:
    if keyEscape.tapped: quitApp()

    sys.buffer.clear(col1)
    sys.buffer.resize(fau.sizei div scl.int)
    
    fau.cam.update(fau.size / scl, player.fetch(Pos).vec2)
    fau.cam.use()

    drawBuffer(sys.buffer)
  
  finish:
    discard

template randRect(amount: int, seed: int, mutator, code: untyped) =
  block:
    let view = fau.cam.viewport.grow(fau.cam.size.x)
    let r = 1000f

    var ra {.inject.} = initRand(seed)

    for i in 0..<amount:
      var pos {.inject.} = vec2(ra.rand(-r..r), ra.rand(-r..r)) + vec2(fau.time * scl, sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)))
      pos += mutator
      pos -= view.pos
      pos = vec2(pos.x.emod view.w, pos.y.emod view.h)
      pos += view.pos

      code

sys("particles", [Main]):
  start:
    let 
      fish = "fish".patch
      bubble = "bubble".patch

    randRect(40, 0):
      vec2(sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)), fau.time * ra.rand(0.9f..4f) * 4f)
    do:
      draw(bubble, pos, scl = vec2(ra.rand(0.6f..1.2f)), color = col2)

    randRect(50, 0):
      vec2(fau.time * ra.rand(1f..4f) * 3f, sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)))
    do:
      draw(fish, pos, scl = vec2(-1f + sin(fau.time, ra.rand(0.1f..0.3f), 0.06f), 1f), color = col2)


sys("drawPlayer", [Player, Pos, Vel]):
  all:
    draw("player".patch, item.pos.vec2, rotation = item.vel.rot - 90f.rad, scl = vec2(1f, 1f + sin(item.vel.moveTime, 0.1f, 0.13f)), color = col3)

makeEffectsSystem()

sys("endDraw", [Main]):
  start:
    drawBufferScreen()
    sysDraw.buffer.blit()

launchFau("New Year's Jam 2021")
