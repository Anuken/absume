import ecs, fau/presets/[basic, effects]

static: echo staticExec("faupack -p:../assets-raw/sprites -o:../assets/atlas")

const scl = 4.0

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32

sys("init", [Main]):

  init:
    discard

  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.update(fau.size / scl)
    fau.cam.use()

    fillPoly(vec2(0, 0), 6, 30)
  
  finish:
    discard

launchFau("nyj")
