import ecs, fau/presets/[basic, effects], fau/util/util, math, random, strformat, fau/audio

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas --min:2048 --max:2048")

const
  #palette
  col1 = %"172B4C"
  col2 = %"03113F"
  col3 = %"3960B5"

  #level constants
  speeds = [1f, 1.13f, 1.13f, 1.23]
  dashSpeeds = [1f, 1.3f, 1.3f, 1.5f]
  darknessLevels = [0f, 0.1f, 1f, 1f]
  lightRadii = [0f, 40f, 170f, 160f]
  monsterOffsets = [-180f.rad, 90f.rad, 90f.rad, -180f.rad]

  monsterBoxes = [
    rect(42f, 362f, 1265f, 222f),
    rect(116f, 82f, 309f, 447f),
    rect(100f, 190f, 509f, 233f),
    rect(120f, 220f, 521f, 459f)
  ]

  playerSpeed = 7f
  #targetHeight = 300 #unused
  targetWidth = 600
  fishSpawned = 35
  despawnRange = targetWidth * 3
  monsterDespawnRange = targetWidth * 5f
  sclPerForm = 0.05f
  lightLayer = 10f
  soundInterval = 5f..8f
  firstSpawnDelay = 10f

var 
  ended = false
  started = false
  ending = false
  endSize = 0f
  endTimer = 0f
  startSize = 1f
  monsterSounds: array[4, seq[Sound]]
  player: EntityRef
  pieces: array[6, Patch]
  shakeTime: float32
  playerPos: Vec2
  drawLight: bool
  darkAlpha = 0f
  coverAlpha = 0f
  curForm = 0
  deathTimer = 0f
  monsterMinDst = 0f
  globalLowpass: BiquadFilter
  noiseVoice: Voice
  firstSpawnTimer = 0f

template fishTarget(): int = 5 + curForm * 2

template spawnFish(ftier: int, pos: Vec2) =
  let p = pos
  discard newEntityWith(Vel(rot: rand(6f)), Pos(x : p.x, y: p.y), Fish(dashCooldown: rand(1f..11f), tier: ftier, variant: rand(1..3), size: 2f, speedMult: rand(-0.2f..0.1f), sizeMult: rand(-0.25f..0.2f)))

template spawnMonster(ftier: int, pos: Vec2) =
  let p = pos
  discard newEntityWith(Vel(rot: (p - playerPos).angle + monsterOffsets[ftier]), Pos(x: p.x, y: p.y), Monster(tier: ftier, radius: patch("monster" & $(ftier + 1)).width / 2f))

template sound(sounds: openArray[Sound]): Sound = sample(sounds)

proc calcVoice(pos: Vec2, dst: float32): tuple[pan: float32, vol: float32, lop: float32] =
  let 
    xdst = pos.x - playerPos.x
    pan = if xdst.abs <= 200f: 0f else: clamp(xdst / 800f, -1f, 1f)
    volDst = targetWidth * 3.1f
    #0 to 1 as player gets closer; should it be exponential?
    volScl = max(1f - dst / volDst, 0f).pow(1.1f)
    #0 to 1 as player gets closer; lifted up as low-pass only applies when really far away
    lopScl = max(1f - dst / volDst, 0f).powout(2f)

    lopMin = 70f
    lopMax = 500f
  
  return (pan, volScl, lerp(lopMin, lopMax, lopScl))

proc updateSound(voice: Voice, pos: Vec2, dst: float32) =
  if voice.valid:
    let params = calcVoice(pos, dst)
    voice.pan = params.pan
    voice.volume = params.vol
    voice.setFilterParam(0, biquadFrequency, params.lop)

proc monsterSound(sounds: seq[Sound], pos: Vec2, dst: float32): Voice =
  let params = calcVoice(pos, dst)

  globalLowpass.setLowpass(params.lop)
  
  let sound = sounds.sample
  sound.setFilter(0, globalLowpass)
  return sound.play(pitch = rand(0.8f..1.1f), volume = params.vol, pan = params.pan)

template reset() =
  sysAll.clear()
  shakeTime = 0f
  curForm = 0
  monsterMinDst = 0f
  deathTimer = 0f
  firstSpawnTimer = 0f
  player = newEntityWith(Vel(), Pos(), Player(form: 0, fishEaten: 0))

  const spread = 800f
  for i in 0..10:
    spawnFish(0, vec2(rand(-spread..spread), rand(-spread..spread)))

proc shake(intensity: float32) = shakeTime = max(shakeTime, intensity)

template checkForm() =
  let p = player.fetch(Player)
  if p.fishEaten >= fishTarget() and p.form < speeds.len - 1:
    p.form.inc
    p.fishEaten = 0
    effectFormUpgrade(player.fetch(Pos).vec2)
    soundMutate.play(pitch = rand(0.9f..1.1f))

template spawnDolphins(): bool = curForm == 3 and player.fetch(Player).fishEaten >= fishTarget()

template pitched(): float32 = rand(0.9f..1.1f)

proc light(pos: Vec2, radius = 100f) =
  if drawLight and radius > 1f:
    draw("light".patch, pos, size = vec2(radius * 2f), z = lightLayer, blend = blendAdditive)

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
    particlesLife(e.id, (e.rotation * 13).int, e.pos, e.fin.powout(3f), 50f):
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
      dashTime: float32
    Player = object
      segments: array[4, float32]
      form: int
      fishEaten: int
      lightRadius: float32
    Fish = object
      tier: int
      dashCooldown: float32
      shrink: float32
      variant: int
      size: float32
      scare: float32
      speedMult: float32
      sizeMult: float32
      segments: array[3, float32]
    Monster = object
      tier: int
      radius: float32
      soundTimer: float32
      lastVoice: Voice

sys("all", [Pos]):
  init:
    reset()

    monsterSounds = [
      @[soundM11, soundM12],
      @[soundM21, soundM22],
      @[soundM31, soundM32],
      @[soundM41, soundM42]
    ]

    #TODO might be better to bake these into the sounds.
    soundDash.setFilter(0, newLowpassFilter(110f))
    soundEat.setFilter(0, newLowpassFilter(400f))
    soundBubble.setFilter(0, newLowpassFilter(220f))
    soundBubble2.setFilter(0, newLowpassFilter(240f))

    globalLowpass = newLowpassFilter(2000f)
    soundNoise.setFilter(0, globalLowpass)

makeTimedSystem()

sys("spawnFish", [Main]):
  fields:
    timer: float32
  start:
    let p = player.fetch(Player)
    let toSpawn = if spawnDolphins(): 4 else: curForm

    if sysFish.counts[toSpawn] < fishSpawned - p.fishEaten:
      #spawn a fish every x seconds
      incTimer(sys.timer, 1f / 1f * fau.delta):
        let vec = vec2l(rand(360f.rad), targetWidth.float32 * rand(1.5f..2.5f)) + fau.cam.pos
        spawnFish(toSpawn, vec)

sys("fish", [Fish, Vel, Pos]):
  fields:
    counts: array[6, int]

  start:
    let pp = player.fetch(Pos).vec2
    let pcomp = player.fetch(Player)

    for i in sys.counts.mitems:
      i = 0
  all:
    const speedPerTier = 0.24f

    #despawn when not in range anymore
    let dst = item.pos.vec2.dst(pp)
    if dst > despawnRange:
      sys.deleteList.add item.entity

    if item.fish.tier < curForm:
      item.fish.shrink += fau.delta / 1f
      if item.fish.shrink >= 1f:
        sys.deleteList.add item.entity

    var speed = 2.5f * (1f + item.fish.speedMult + speedPerTier * item.fish.tier)

    #record count increase
    sys.counts[item.fish.tier].inc

    item.vel.rot += sin(fau.time + item.entity.entityId.float32*3f, 0.5, 0.01f) + cos(fau.time + item.entity.entityId.float32*5f, 3f, 0.01f)

    let avoidAngle = (item.pos.vec2 - pp).angle

    #avoid player
    if dst < 90f + item.fish.tier * 9f:
      item.vel.rot = item.vel.rot.aapproach(avoidAngle, 2.5f * fau.delta * (0.2f + item.fish.tier * 0.5f))
      item.fish.scare = item.fish.scare.lerp(1f, 1f * fau.delta)

      if chance(1.7f * fau.delta):
        effectBubbleSmall(item.pos.vec2 + vec2l(item.vel.rot, 11f) + randVec(7f), rot = rand(0.4f..0.6f))
    else:
      item.fish.scare = item.fish.scare.lerp(0f, 2f * fau.delta)

    item.vel.vec *= (1f - fau.delta * 4f)

    let delta = vec2l(item.vel.rot, speed * fau.delta * (1f + item.fish.scare * 2.2f))
    item.vel.vec += delta

    item.pos.x += item.vel.vec.x
    item.pos.y += item.vel.vec.y

    item.fish.dashCooldown -= fau.delta * (1f + item.fish.tier * 0.3f)

    if item.fish.tier >= 1 and item.vel.dashTime <= -2 and item.fish.dashCooldown <= 0f and item.fish.scare >= 0.13f:
      item.vel.vec += delta * 40f
      item.vel.dashTime = 1f
      item.fish.dashCooldown = rand(1f..4f)
      #dolphins annoying
      if item.fish.tier == 4:
        item.fish.dashCooldown += 1f

    item.vel.moveTime += speed * fau.delta

    let segc = item.fish.segments.len
    let base = item.vel.rot

    for i in 0..<segc:
      item.fish.segments[i] = sin(fau.time + item.entity.entityId.float32 * 3f, 0.12, 0.34f) * item.fish.scare

    if dst <= 16f + item.fish.size:
      effectFishEat(item.pos.vec2, rot = 1f + item.fish.tier * 0.5f)

      soundEat.play(pitch = pitched())

      shake(7f)

      let count = rand(1..4)
      for i in 0..<count:
        effectBubble(item.pos.vec2 + randVec(5f), rot = rand(360f.rad), life = rand(2f..4f))

        soundBubble.play(pitch = rand(0.4f..0.6f) * 2f)
      
      if curForm == item.fish.tier:
        pcomp.fishEaten.inc
        checkForm()

      sys.deleteList.add item.entity

      #dolphin gotten, end of game
      if item.fish.tier == 4:
        ending = true


sys("monsterSpawn", [Monster, Vel, Pos]):
  fields:
    spawned: bool
  start:
    var count = 0
    var lastPos: Vec2
  all:
    count.inc
    lastPos = item.pos.vec2
  finish:
    if started:
      firstSpawnTimer += fau.delta

    template randTier(): int = max(rand(-1..0) + curForm, 0)
    template randDst(): float32 =  targetWidth.float32 * rand(3.3f..4.1f)

    if firstSpawnTimer >= firstSpawnDelay:
      if count == 0:

        #spawn in front if there's zero
        let dir = if sys.spawned: player.fetch(Vel).rot + rand(-1f..1f).rad * 0.4f * 0f else: rand(360f).rad
        spawnMonster(randTier(), vec2l(dir, randDst()) + fau.cam.pos)

        sys.spawned = true
      elif count == 1 and curForm >= 1: 
        #spawn behind prev if there's already one monster, surrounding the player
        spawnMonster(randTier(), -(lastPos - fau.cam.pos).nor * randDst() + fau.cam.pos)
      elif count == 2 and curForm >= 2: 
        #spawn below or above player at random
        let 
          base = -(lastPos - fau.cam.pos).nor
          dir1 = (rand(0..1).float32 - 0.5f) * 2f * 90f.rad

        spawnMonster(randTier(), base.rotate(dir1) * randDst() + fau.cam.pos)
        if count == 3 and curForm >= 3:
          spawnMonster(randTier(), base.rotate(-dir1) * randDst() + fau.cam.pos)

sys("monsterMove", [Monster, Vel, Pos]):
  start:
    monsterMinDst = 999999999f
    let p = player.fetch(Player)
    let pp = player.fetch(Pos).vec2
  all:
    
    let 
      vec = pp - item.pos.vec2
      speed = 19f + item.monster.tier.float32*7f

      bh = monsterBoxes[item.monster.tier]
      p = patch(&"monster{item.monster.tier + 1}")
      topLeft = item.pos.vec2 + p.size/2f * vec2(-1f, 1f) + vec2(bh.x, -bh.y)

      hitRect = rect(
        topLeft.x,
        topLeft.y - bh.h,
        bh.w,
        bh.h
      )

      relativepp = (pp - item.pos.vec2).rotate(-item.vel.rot) + item.pos.vec2

    #despawn
    if not within(pp, item.pos.vec2, monsterDespawnRange + item.monster.radius):
      sys.deleteList.add item.entity

    #delete "outdated" bosses that are reasonably far away
    if item.monster.tier < curForm - 1 and not within(pp, item.pos.vec2, targetWidth * 2.4f + item.monster.radius):
      sys.deleteList.add item.entity
    
    let
      dst = (hitRect.dst(relativepp))
      delta = vec.lim(1f) * speed * fau.delta

    monsterMinDst = dst.min(monsterMinDst)

    if item.monster.soundTimer <= 0f:
      item.monster.lastVoice = monsterSound(monsterSounds[item.monster.tier], item.pos.vec2, dst)
      item.monster.soundTimer = rand(soundInterval)
    else:
      updateSound(item.monster.lastVoice, item.pos.vec2, dst)

    item.monster.soundTimer -= fau.delta

    item.pos.x += delta.x
    item.pos.y += delta.y

    item.vel.rot = aapproach(item.vel.rot, (delta.angle - monsterOffsets[item.monster.tier]).mod(360f.rad), 0.02f * fau.delta)

sys("playerMove", [Player, Vel, Pos]):
  all:
    curForm = item.player.form

    var ax = vec2(axis(keyA, keyD), axis(keyS, keyW))
    
    if keyMouseLeft.down:
      ax = (fau.mouse - fau.size/2f).nor

    let 
      dmult = dashSpeeds[item.player.form]
      smult = speeds[item.player.form]
      vec = ax.lim(1f) * playerSpeed * fau.delta * smult
    
    if vec.len > 0:
      started = true
      item.vel.rot = item.vel.rot.alerp(vec.angle, 2.4f * fau.delta)
    
    item.vel.vec *= (1f - fau.delta * 4f)

    playerPos = item.pos.vec2

    let base = vec.angled(item.vel.rot)
    if vec.len > 0: item.vel.vec += base

    if (keyLShift.tapped or keySpace.tapped or keyMouseRight.tapped) and item.vel.dashTime <= -2f and vec.len > 0:
      item.vel.vec += base * 50f * dmult
      item.vel.dashTime = 1f
      soundDash.play(pitch = pitched())
      shake(3f)
      started = true

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
        if chance(0.5f):
          sound([soundBubble, soundBubble2]).play(pitch = rand(0.4f..0.5f), volume = 0.2f)
        effectBubble(item.pos.vec2 + vec2l(item.vel.rot, 11f) + randVec(7f), rot = 90f.rad)

sys("dasher", [Vel, Pos]):
  all:
    if item.vel.dashTime > 0:
      incTimer(item.vel.bub, 30f / 60f):
        effectDash(item.pos.vec2 + randVec(2f), item.vel.rot)

        if chance(0.3):
          soundBubble.play(pitch = rand(0.3f..0.5f))
    
    item.vel.dashTime -= fau.delta * 1.8f

sys("draw", [Main]):
  fields:
    buffer: Framebuffer
    lights: Framebuffer
    lightShader: Shader
    dither: Texture

  init:
    sys.dither = loadTexture("dither.png")
    sys.dither.wrap = twRepeat
    sys.buffer = newFramebuffer()
    sys.lights = newFramebuffer()
    sys.lightShader = newShader(screenspaceVertex, """
    #define ditherSize vec2(8.0)

    uniform sampler2D u_texture;
    uniform sampler2D u_dither;
    uniform vec4 u_color;
    uniform vec2 u_pos;
    uniform vec2 u_res;
    uniform float u_cover;
    uniform float u_alpha;

    varying vec2 v_uv;

    void main(){
      float a = (texture2D(u_texture, v_uv).a + (1.0 - u_alpha)) * (1.0 - u_cover);
      vec2 coords = v_uv * u_res + u_pos;
      float dsample = texture2D(u_dither, coords / ditherSize).r;
      float result = step(dsample, a);

      gl_FragColor = mix(u_color, vec4(0.0), result);
    }
    """)

    for i, piece in pieces.mpairs:
      piece = patch(&"piece{i + 1}")

  start:
    if keyEscape.tapped: quitApp()

    let scl = fau.size.x / targetWidth.float32

    var maxDst = 720f

    let baseMonsterLevel = (max(maxDst - monsterMinDst, 0f) / maxDst)
    let monsterLevel = baseMonsterLevel.pow(3f)
    let touching = baseMonsterLevel >= 0.95f
    let monsterAlpha = lerp(0f, 1f, monsterLevel)

    shake(monsterLevel * 11f)

    if monsterLevel >= 0.5f and coverAlpha >= 0.94f:
      deathTimer += fau.delta
      if deathTimer >= 0.5f or monsterLevel >= 0.99f:
        reset()
    else:
      deathTimer -= fau.delta
      deathTimer = max(deathTimer, 0f)

    coverAlpha = lerp(coverAlpha, monsterAlpha, (3f + monsterLevel*3f) * (1f + touching.float32 * 5f) * fau.delta)
    darkAlpha = lerp(darkAlpha, darknessLevels[curForm] + ending.float32 * 1.3f, 1.5f * fau.delta)

    if ending:
      shake(9f)

      if darkAlpha >= 2f:
        ended = true
        sysSpawnFish.paused = true
        sysMonsterMove.paused = true
        sysPlayerMove.paused = true
        sysFish.clear()
        sysMonsterMove.clear()
      
    if ended:
      endTimer += fau.delta
      if endTimer >= 1f:
        endSize = lerp(endSize, 1f, 1f * fau.delta)

    drawLight = darkAlpha > 0 or coverAlpha > 0

    if monsterAlpha > 0.01f:
      let vol = monsterAlpha * 6f

      if not noiseVoice.valid:
        noiseVoice = soundNoise.play(volume = vol, loop = true, pitch = 0.24f)
      
      noiseVoice.volume = vol
      noiseVoice.setFilterParam(0, biquadFrequency, 2000f)
    elif noiseVoice.valid:
      noiseVoice.volume = noiseVoice.volume - 4f * fau.delta
      if noiseVoice.volume <= 0.01f:
        noiseVoice.stop()

    sys.buffer.clear(col1)
    sys.buffer.resize((fau.size / scl).vec2i)

    if drawLight:
      sys.lights.clear(colorClear)
      sys.lights.resize(sys.buffer.size)

    var offset = vec2()
    if shakeTime > 0:
      offset = randVec(shakeTime)
      shakeTime -= fau.delta * 60f
    
    fau.cam.update(fau.size / scl, player.fetch(Pos).vec2 + offset)
    fau.cam.use()

    drawBuffer(sys.buffer)

    if drawLight:
      drawLayer(lightLayer, proc() = drawBuffer(sysDraw.lights)) do:
        drawBuffer(sysDraw.buffer)

        fau.quad.render(sysDraw.lightShader, meshParams(buffer = sysDraw.buffer, blend = blendNormal)):
          texture = sysDraw.lights.sampler
          dither = sysDraw.dither.sampler(1)
          color = col2
          pos = fau.cam.pos
          res = sysDraw.lights.size.vec2
          alpha = darkAlpha
          cover = coverAlpha


    if startSize > 0.01f:
      draw("start".patch, fau.cam.pos + vec2(0, fau.cam.height * (1f - startSize)), scl = vec2(startSize), z = lightLayer + 5f)
    
    if started:
      startSize = lerp(startSize, 0f, fau.delta * 4f)
    
    if ended:
      draw("end".patch, fau.cam.pos, scl = vec2(endSize), z = lightLayer + 5f)

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

sys("drawMonsters", [Pos, Monster, Vel]):
  all:
    var divs: array[12, float32]
    var rot = fau.time.sin(1.2f, 0.04f)
    for i, f in divs.mpairs:
      f = sin(fau.time + i.float32 * 2f, 1.7f, 0.034f)
    drawBend(patch(&"monster{item.monster.tier + 1}"), item.pos.vec2, divs, divs.len div 2, rotation = item.vel.rot, mixColor = col2)

sys("drawFish", [Fish, Pos, Vel]):
  all:
    let p = (&"tier{item.fish.tier + 1}fish{item.fish.variant}").patch
    drawBend(p,
      item.pos.vec2 - vec2l(item.vel.rot, p.width / 4f), 
      item.fish.segments,
      1,
      rotation = item.vel.rot, 
      mixColor = col3,
      scl = vec2((1f + sin(item.vel.moveTime, 3.5f, 0.07f)), -(item.vel.rot >= 90f.rad and item.vel.rot < 270f.rad).sign) * (1f + item.fish.sizeMult) * lerp(1f, 0f, item.fish.shrink),
      z = lightLayer + 2
    )

const offsets = [vec2(-5f, 0f), vec2(), vec2(4f, 0f)]

sys("drawPlayer", [Player, Pos, Vel]):
  all:
    item.player.lightRadius = item.player.lightRadius.lerp(lightRadii[item.player.form], 0.6f * fau.delta)

    light(item.pos.vec2, item.player.lightRadius)

    let scling = 1f + sclPerForm * item.player.form.float32
    var dash = item.vel.dashTime.max(0f)

    for i in 0..2:
      var off = offsets[i].rotate(item.player.segments[1])

      draw((&"form{item.player.form}-{i}").patch,
        item.pos.vec2 + off, 
        rotation = item.player.segments[i], 
        scl = vec2(dash * 0.3f + 1f + sin(item.vel.moveTime, 0.1f, 0.09f), -(item.vel.rot >= 90f.rad and item.vel.rot < 270f.rad).sign) * scling, 
        mixColor = col3
      )

makeEffectsSystem()

sys("endDraw", [Main]):
  start:
    drawBufferScreen()
    sysDraw.buffer.blit()

launchFau("Absume")
