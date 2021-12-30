import ecs, fau/presets/[basic, effects], fau/util/util, math, random, strformat

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas")

#palette
const
  col1 = %"110f25"
  col2 = %"4f6b7a"
  col3 = %"a7c6c5"

const 
  playerSpeed = 7f
  #targetHeight = 300 #TODO unused
  targetWidth = 600
  fishSpawned = 50
  despawnRange = targetWidth * 3
  sclPerForm = 0.09f
  speeds = [1f, 1.13f, 1.1f, 1.1f]
  dashSpeeds = [1f, 1.4f, 1.4f, 1.4f]

const origins = [vec2(18f, 9f), vec2(24.5f, 9.5f), vec2(30f, 9f)]

var 
  player: EntityRef
  pieces: array[6, Patch]
  shakeTime: float32
  playerPos: Vec2

template fishTarget(): int = 5 + player.fetch(Player).form * 2

template spawnFish(ftier: int, pos: Vec2) =
  let p = pos
  discard newEntityWith(Vel(rot: rand(6f)), Pos(x : p.x, y: p.y), Fish(tier: ftier, variant: rand(1..2), size: 2f, speedMult: rand(-0.2f..0.1f), sizeMult: rand(-0.25f..0.2f)))

proc shake(intensity: float32) = shakeTime = max(shakeTime, intensity)

template checkForm() =
  let p = player.fetch(Player)
  if p.fishEaten >= fishTarget() and p.form < speeds.len - 1:
    p.form.inc
    p.fishEaten = 0
    effectFormUpgrade(player.fetch(Pos).vec2)

defineEffects:
  bubble(lifetime = 1f):
    let off = vec2l(e.rotation, e.fin.powout(3f) * 7f)
    poly(e.pos + off, 10, 4f + 4f * e.fin.pow(4f), stroke = 2f * e.fout, color = col3)
    fillCircle(e.pos + vec2(1.1f) + off, 2f * e.fout, color = col3)
  bubbleSmall(lifetime = 1f):
    let off = vec2l(90f.rad, e.fin.powout(3f) * 7f)
    poly(e.pos + off, 10, e.rotation * 4f + (e.rotation * 4f) * e.fin.pow(4f), stroke = 2f * e.fout, color = col3)
    fillCircle(e.pos + vec2(1.1f) * e.rotation + off, e.rotation * 2f * e.fout, color = col3)
  dash(lifetime = 0.7f):
    particlesAngle(e.id, 2, e.pos, 29 * e.fin, e.rotation, 40f.rad):
      fillCircle(pos, 4f * e.fout, color = col3)
  fishEat(lifetime = 7f):
    particlesLife(e.id, 20, e.pos, e.fin.powout(3f), 50f):
      draw(pieces[count mod pieces.len], pos, scl = vec2(0.9f * fout.powout(3f)), rotation = rot + count * 20f.rad, color = col3)
  formUpgrade(lifetime = 1.5f):
    particlesLife(e.id, 30, playerPos, e.fout, 44f):
      fillCircle(pos, 4f * fout.powout(3f), color = col3)
    
    poly(playerPos, 20, 30f * e.fin.powout(3f), stroke = 3f * e.fout, color = col3)

registerComponents(defaultComponentOptions):
  type
    Vel = object
      vec: Vec2
      rot: float32
      bub: float32
      moveTime: float32
    Player = object
      segments: array[4, float32]
      form: int
      dashTime: float32
      fishEaten: int
    Fish = object
      tier: int
      shrink: float32
      variant: int
      size: float32
      scare: float32
      speedMult: float32
      sizeMult: float32
      segments: array[3, float32]

sys("init", [Main]):
  init:
    player = newEntityWith(Vel(), Pos(), Player())

    const spread = 800f
    for i in 0..24:
      spawnFish(0, vec2(rand(-spread..spread), rand(-spread..spread)))

makeTimedSystem()

sys("fish", [Fish, Vel, Pos]):
  fields:
    counts: array[5, int]

  start:
    #TODO spawn fish
    let pp = player.fetch(Pos).vec2
    let pcomp = player.fetch(Player)

    for i in sys.counts.mitems:
      i = 0
  all:
    const speedPerTier = 0.11f

    #despawn when not in range anymore
    let dst = item.pos.vec2.dst(pp)
    if dst > despawnRange:
      sys.deleteList.add item.entity

    if item.fish.tier != pcomp.form:
      item.fish.shrink += fau.delta / 1f
      if item.fish.shrink >= 1f:
        sys.deleteList.add item.entity

    var speed = 30f * (1f + item.fish.speedMult + speedPerTier * item.fish.tier)

    #record count increase
    sys.counts[item.fish.tier].inc

    item.vel.rot += sin(fau.time + item.entity.entityId.float32*3f, 0.5, 0.01f) + cos(fau.time + item.entity.entityId.float32*5f, 3f, 0.01f)

    let avoidAngle = (item.pos.vec2 - pp).angle

    #avoid player
    if dst < 90f:
      item.vel.rot = item.vel.rot.aapproach(avoidAngle, 2.5f * fau.delta)
      item.fish.scare = item.fish.scare.lerp(1f, 1f * fau.delta)

      if chance(1.7f * fau.delta):
        effectBubbleSmall(item.pos.vec2 + vec2l(item.vel.rot, 11f) + randVec(7f), rot = rand(0.4f..0.6f))
    else:
      item.fish.scare = item.fish.scare.lerp(0f, 2f * fau.delta)

    let delta = vec2l(item.vel.rot, speed * fau.delta * (1f + item.fish.scare * 2.2f))
    item.pos.x += delta.x
    item.pos.y += delta.y

    item.vel.moveTime += speed * fau.delta

    let segc = item.fish.segments.len
    let base = item.vel.rot

    for i in 0..<segc:
      item.fish.segments[i] = sin(fau.time + item.entity.entityId.float32 * 3f, 0.12, 0.34f) * item.fish.scare

    #TODO hitbox size?
    if dst <= 16f + item.fish.size and pcomp.form == item.fish.tier:
      effectFishEat(item.pos.vec2) #TODO vary size

      shake(7f)

      let count = rand(1..4)
      for i in 0..<count:
        effectBubble(item.pos.vec2 + randVec(5f), rot = rand(360f.rad), life = rand(2f..4f))
      
      #TODO level up
      if pcomp.form == item.fish.tier:
        pcomp.fishEaten.inc
        checkForm()

      sys.deleteList.add item.entity
    #TODO AI

sys("spawn", [Main]):
  fields:
    timer: float32
  start:
    let p = player.fetch(Player)
    let ctier = p.form

    if sysFish.counts[ctier] < fishSpawned - p.fishEaten:
      #spawn a fish every x seconds
      incTimer(sys.timer, 1f / 1f * fau.delta):
        let vec = vec2l(rand(360f.rad), targetWidth.float32 * rand(1f..1.9f)) + fau.cam.pos
        spawnFish(ctier, vec)

sys("playerMove", [Player, Vel, Pos]):
  all:
    let 
      dmult = dashSpeeds[item.player.form]
      smult = speeds[item.player.form]
      vec = vec2(axis(keyA, keyD), axis(keyS, keyW)).lim(1f) * playerSpeed * fau.delta * smult
    
    if vec.len > 0:
      item.vel.rot = item.vel.rot.alerp(vec.angle, 2.4f * fau.delta)
    
    item.vel.vec *= (1f - fau.delta * 4f)

    playerPos = item.pos.vec2

    let base = vec.angled(item.vel.rot)
    if vec.len > 0: item.vel.vec += base

    if (keyLShift.tapped or keySpace.tapped) and item.player.dashTime <= -2f and vec.len > 0:
      item.vel.vec += base * 50f * dmult
      item.player.dashTime = 1f
      shake(3f)

    item.player.dashTime -= fau.delta * 1.8f

    if item.player.dashTime > 0:
      incTimer(item.vel.bub, 30f / 60f):
         effectDash(item.pos.vec2 + randVec(2f), item.vel.rot)

    item.pos.x += item.vel.vec.x
    item.pos.y += item.vel.vec.y

    #idle
    if item.vel.vec.len < 0.1f:
      item.player.segments[1] += sin(fau.time, 0.6, 0.01f)

    for i in 0..2:
      let next = if i == 2: item.vel.rot else: item.player.segments[i + 1]
      item.player.segments[i] = aclamp(item.player.segments[i].alerp(next, 4f * fau.delta), next, 20f.rad)

    if vec.len > 0:
      item.player.segments[0] += sin(fau.time, 0.14, 0.02f)
      item.player.segments[1] -= sin(fau.time, 0.14, 0.02f)

      item.vel.moveTime += fau.delta
      
      if chance(2f * fau.delta):
        effectBubble(item.pos.vec2 + vec2l(item.vel.rot, 11f) + randVec(7f), rot = 90f.rad)

sys("draw", [Main]):
  fields:
    buffer: Framebuffer

  init:
    sys.buffer = newFramebuffer()

    for i, piece in pieces.mpairs:
      piece = patch(&"piece{i + 1}")

  start:
    if keyEscape.tapped: quitApp()

    let scl = fau.size.x / targetWidth.float32#fau.size.y / targetHeight.float32

    sys.buffer.clear(col1)
    sys.buffer.resize((fau.size / scl).vec2i)

    var offset = vec2()
    if shakeTime > 0:
      offset = randVec(shakeTime)
      shakeTime -= fau.delta * 60f
    
    fau.cam.update(fau.size / scl, player.fetch(Pos).vec2 + offset)
    fau.cam.use()

    drawBuffer(sys.buffer)

    #let b = sin(fau.time, 0.5f, 0.3f)
    #drawBend("dolphin1".patch, vec2(), [b, b, b, b], 2, color = colorRed)
    #draw("dolphin1".patch, vec2(0f, -14f))
  
  finish:
    discard

template randRect(amount: int, seed: int, mutator, code: untyped) =
  block:
    let view = fau.cam.viewport.grow(fau.cam.size.x)
    let r = 1000f

    var ra {.inject.} = initRand(seed)

    for i in 0..<amount:
      var pos {.inject.} = vec2(ra.rand(-r..r), ra.rand(-r..r)) + vec2(fau.time * 4f, sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)))
      pos += mutator
      pos -= view.pos
      pos = vec2(pos.x.emod view.w, pos.y.emod view.h)
      pos += view.pos

      code

sys("particles", [Main]):
  start:
    let 
      fish = "fish".patch
      fish2 = "xenofish".patch
      bubble = "bubble".patch

    randRect(45, 1):
      vec2(sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)), fau.time * ra.rand(0.9f..4f) * 4f)
    do:
      draw(bubble, pos, scl = vec2(ra.rand(0.6f..1.2f)), color = col2)

    randRect(50, 2):
      vec2(fau.time * ra.rand(1f..4f) * 1f, sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)))
    do:
      draw(fish, pos, scl = vec2(-1f + sin(fau.time, ra.rand(0.1f..0.3f), 0.06f), 1f) * 0.4f, color = col2)

    randRect(60, 3):
      vec2(fau.time * ra.rand(1f..4f) * 3f, sin(fau.time, ra.rand(0.7f..1.5f), ra.rand(0f..4f)))
    do:
      draw(if ra.rand(1f) > 0.8: fish2 else: fish, pos, scl = vec2(-1f + sin(fau.time, ra.rand(0.1f..0.3f), 0.06f) * 0.6f, 1f) * 0.6f, mixcolor = col2)

sys("drawFish", [Fish, Pos, Vel]):
  all:
    drawBend((&"tier{item.fish.tier + 1}fish{item.fish.variant}").patch,
      item.pos.vec2, 
      item.fish.segments,
      1,
      rotation = item.vel.rot, 
      mixColor = col3,
      scl = vec2((1f + sin(item.vel.moveTime, 3.5f, 0.07f)), -(item.vel.rot >= 90f.rad and item.vel.rot < 270f.rad).sign) * (1f + item.fish.sizeMult) * lerp(1f, 0f, item.fish.shrink)
    )

const offsets = [vec2(-5f, 0f), vec2(), vec2(4f, 0f)]

sys("drawPlayer", [Player, Pos, Vel]):
  all:
    let scling = 1f + sclPerForm * item.player.form.float32
    var dash = item.player.dashTime.max(0f)
    case item.player.form:
    of 0, 1:
      for i in 0..2:
        var off = offsets[i].rotate(item.player.segments[1])

        draw((&"form{item.player.form}-{i}").patch,
         item.pos.vec2 + off, 
         rotation = item.player.segments[i], 
         scl = vec2(dash * 0.3f + 1f + sin(item.vel.moveTime, 0.1f, 0.09f), -(item.vel.rot >= 90f.rad and item.vel.rot < 270f.rad).sign) * scling, 
         mixColor = col3
        )
    else: discard

makeEffectsSystem()

sys("endDraw", [Main]):
  start:
    drawBufferScreen()
    sysDraw.buffer.blit()

launchFau("New Year's Jam 2021")