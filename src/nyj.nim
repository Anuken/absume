import ecs, fau/presets/[basic, effects]

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas")

const 
  scl = 4f
  playerSpeed = 45f

var player: EntityRef

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y, rot: float32
    
    Player = object

sys("move", [Player, Vel, Pos]):
  all:
    let vec = vec2(axis(keyA, keyD), axis(keyS, keyW)).lim(1f) * playerSpeed * fau.delta
    if vec.len > 0:
      item.vel.rot = aapproach(item.vel.rot, vec.angle, 3f * fau.delta)
    
    let base = vec.angled(item.vel.rot)

    item.pos.x += base.x
    item.pos.y += base.y

sys("draw", [Main]):
  fields:
    buffer: Framebuffer

  init:
    player = newEntityWith(Vel(), Pos(), Player())
    sys.buffer = newFramebuffer()

  start:
    if keyEscape.tapped: quitApp()

    sys.buffer.clear()
    sys.buffer.resize(fau.sizei div scl.int)
    
    fau.cam.update(fau.size / scl)
    fau.cam.use()

    drawBuffer(sys.buffer)
  
  finish:
    discard

sys("drawPlayer", [Player, Pos, Vel]):
  all:
    draw("player".patch, item.pos.vec2, rotation = item.vel.rot - 90f.rad)

sys("endDraw", [Main]):
  start:
    drawBufferScreen()
    sysDraw.buffer.blit()

launchFau("New Year's Jam 2021")
