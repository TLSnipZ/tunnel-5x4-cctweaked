-- tunnel54.lua
-- 5x4 Tunnel Miner mit Ender-Modem (unendliche Range), Auto-Return, Torches,
-- Resume, getrennte Kanaele: turtleLog (immer) & turtleChat (Funny/Verbose),
-- Live-Status, gezielte Fernsteuerung via rednet.host("turtleCtl", <name>).
-- ASCII-only (ae/oe/ue/ss). CC:Tweaked.

-- ====== Config ======
local WIDTH, HEIGHT = 5, 4
local TORCH_INTERVAL = 6
local TORCH_NAME = "minecraft:torch"
local STATE_FILE = "tunnel54.state"
local CFG_FILE   = "tunnel54.cfg"
local VERBOSE = true  -- Funny/Chat default an

-- CFG MUSS FRUEH DA SEIN, sonst nil-Fehler bei say()/sendLog()
local CFG = {}

-- ====== ASCII helper ======
local function de(s)
  s = s:gsub("Ä","Ae"):gsub("Ö","Oe"):gsub("Ü","Ue")
  s = s:gsub("ä","ae"):gsub("ö","oe"):gsub("ü","ue"):gsub("ß","ss")
  return s
end

-- ====== Modems oeffnen (Ender inkl.) ======
local function openAnyModems()
  for _,side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then pcall(rednet.open, side) end
  end
end
openAnyModems()

-- ====== Inventar-Utils ======
local function slotsFree()
  local f=0
  for s=1,16 do if turtle.getItemCount(s)==0 then f=f+1 end end
  return f
end
local function invFull()
  for s=1,16 do if turtle.getItemCount(s)==0 then return false end end
  return true
end

-- ====== Chat/Funny + Log ======
local function say(fmt, ...)
  local name = CFG.name or "turtle"
  local msg = de(string.format("[%s] ", name) .. string.format(fmt, ...))
  print("🐢 "..msg)
  if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
end

local function sendLog(step, wIdx, goingRight, length)
  local lvl = turtle.getFuelLevel()
  local log = string.format("[%s] step %d/%d col %d/%d dir %s fuel %s free %d",
    (CFG.name or "turtle"), step, length, wIdx, WIDTH,
    (goingRight and "right" or "left"), tostring(lvl), slotsFree())
  if rednet.isOpen() then rednet.broadcast(log, "turtleLog") end
end

-- ====== Config (Name speichern) ======
local function loadCfg()
  if fs.exists(CFG_FILE) then
    local h=fs.open(CFG_FILE,"r")
    CFG = textutils.unserialize(h.readAll()) or {}
    h.close()
  end
end
local function saveCfg()
  local h=fs.open(CFG_FILE,"w")
  h.write(textutils.serialize(CFG))
  h.close()
end

loadCfg()
if not CFG.name or CFG.name == "" then
  term.setCursorPos(1,1); term.clear()
  print("Turtle-Name eingeben (z.B. alpha/beta):")
  CFG.name = read()
  if not CFG.name or CFG.name == "" then CFG.name = "turtle" end
  saveCfg()
end
if rednet.isOpen() then pcall(rednet.host, "turtleCtl", CFG.name) end

-- ====== Move/Mine ======
local function refuelAll()
  for s=1,16 do
    turtle.select(s)
    if turtle.refuel(0) then turtle.refuel(64) end
  end
  turtle.select(1)
end

local function ensureForward()
  while turtle.detect() do
    local ok, data = turtle.inspect()
    if ok and data and data.name == TORCH_NAME then
      break
    else
      turtle.dig(); sleep(0.05)
    end
  end
  while not turtle.forward() do turtle.attack(); turtle.dig(); sleep(0.05) end
end

local function ensureUp()
  while turtle.detectUp() do turtle.digUp(); sleep(0.05) end
  while not turtle.up() do turtle.attackUp(); turtle.digUp(); sleep(0.05) end
end

local function ensureDown()
  while not turtle.down() do turtle.attackDown(); turtle.digDown(); sleep(0.05) end
end

local function moveRight() turtle.turnRight(); ensureForward(); turtle.turnLeft() end
local function moveLeft()  turtle.turnLeft();  ensureForward(); turtle.turnRight() end

-- >>>>> FIX: 180° drehen und DANN droppen (Ruecken zur Kiste), NICHT zurueckdrehen
local function dumpToChestBehind()
  turtle.turnLeft(); turtle.turnLeft()        -- 180° -> Ruecken zeigt zur Kiste
  for s=1,16 do
    turtle.select(s)
    turtle.drop()                             -- dropt in die Kiste hinter der Turtle
  end
  turtle.select(1)
  -- KEIN weiteres Drehen: bleibt wie Start-Orientierung (Ruecken zur Kiste)
end
-- <<<<< FIX Ende

local function estimateTotalFuel(len) return len*35 + len + 100 end

-- ====== Resume-State ======
local function saveState(step, wIdx, goingRight, length)
  local h=fs.open(STATE_FILE,"w")
  h.write(textutils.serialize({step=step,wIdx=wIdx,goingRight=goingRight,length=length}))
  h.close()
end
local function loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local h=fs.open(STATE_FILE,"r"); local t=textutils.unserialize(h.readAll()); h.close(); return t
end
local function clearState() if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end end

-- ====== Status ======
local function distanceToLeft(wIdx, goingRight)
  if goingRight then return (wIdx-1) else return (WIDTH - wIdx) end
end

local function status(step, wIdx, goingRight, length)
  local reserve=5
  local needHome = distanceToLeft(wIdx,goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()

  if VERBOSE then
    say("Step %d/%d | Col %d/%d | Fuel %s | Heim %d | Frei %d",
      step,length,wIdx,WIDTH,tostring(lvl),needHome,slotsFree())
  end

  local data = {
    type="status", name=(CFG.name or "turtle"),
    step=step, length=length, col=wIdx, width=WIDTH,
    dir=(goingRight and "right" or "left"),
    fuel=lvl, needHome=needHome, slotsFree=slotsFree(), ts=os.time()
  }
  if rednet.isOpen() then rednet.broadcast(data, "turtleStatus") end

  sendLog(step, wIdx, goingRight, length)
end

-- ====== Torches ======
local function placeTorchIfNeeded(step, wIdx)
  if step % TORCH_INTERVAL == 0 and wIdx == 3 then
    for s=1,16 do
      local d=turtle.getItemDetail(s)
      if d and d.name==TORCH_NAME then
        turtle.select(s); turtle.placeDown()
        say("Fackel gesetzt @ step %d", step)
        turtle.select(1); return
      end
    end
  end
end

-- ====== Auto-Return (Slots/Fuel) ======
local function ensureFuelOrReturn(step, wIdx, goingRight, length)
  local reserve=5
  local needHome = distanceToLeft(wIdx,goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  if lvl~="unlimited" and lvl < needHome then
    say("Fuel low -> Heimweg")
    saveState(step,wIdx,goingRight,length)
    for i=1, distanceToLeft(wIdx,goingRight) do moveLeft() end
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    say("@Home - droppen & refuel")
    dumpToChestBehind()                       -- steht danach mit Ruecken zur Kiste
    for i=1,8 do turtle.suck(64) end
    refuelAll()
    for s=1,16 do turtle.select(s); if turtle.getItemCount(s)>0 then turtle.drop() end end
    turtle.select(1)
    turtle.turnLeft(); turtle.turnLeft()      -- wieder Richtung Tunnel
    for i=1, step do ensureForward() end
    for i=1, (wIdx-1) do moveRight() end
    clearState()
  end
end

local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    say("Inventar voll -> Heimweg")
    saveState(step,wIdx,goingRight,length)
    for i=1, distanceToLeft(wIdx,goingRight) do moveLeft() end
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    say("@Home - droppen")
    dumpToChestBehind()                       -- steht danach mit Ruecken zur Kiste
    for i=1,8 do turtle.suck(64) end
    refuelAll()
    for s=1,16 do turtle.select(s); if turtle.getItemCount(s)>0 then turtle.drop() end end
    turtle.select(1)
    turtle.turnLeft(); turtle.turnLeft()      -- wieder Richtung Tunnel
    for i=1, step do ensureForward() end
    for i=1, (wIdx-1) do moveRight() end
    clearState()
  end
end

-- ====== Column & Slice ======
local function clearColumn()
  for i=1, HEIGHT-1 do ensureUp() end
  for i=1, HEIGHT-1 do ensureDown() end
end

-- ====== Remote Control ======
local PAUSED, ABORT = false, false
local function controlListener()
  while true do
    local id, msg, proto = rednet.receive("turtleCtl")
    local cmd = nil
    if type(msg)=="string" then
      cmd = msg:lower()
    elseif type(msg)=="table" then
      if msg.target and msg.target ~= CFG.name then
        cmd = nil
      else
        cmd = (msg.cmd or ""):lower()
      end
    end
    if cmd=="pause"   then PAUSED=true;  say("Pause") end
    if cmd=="resume"  then PAUSED=false; say("Weiter") end
    if cmd=="stop"    then ABORT=true;   say("Stop angefordert") end
    if cmd=="verbose" then VERBOSE=not VERBOSE; say("Verbose=%s", tostring(VERBOSE)) end
  end
end
local function pausePoint() while PAUSED and not ABORT do sleep(0.2) end end

local function doSlice(step, goingRight, length)
  clearColumn()
  maybeAutoReturn(step, 1, goingRight, length)
  ensureFuelOrReturn(step, 1, goingRight, length)
  placeTorchIfNeeded(step, 1)
  status(step, 1, goingRight, length); pausePoint()

  for wIdx=2, WIDTH do
    if goingRight then moveRight() else moveLeft() end
    clearColumn()
    maybeAutoReturn(step, wIdx, goingRight, length)
    ensureFuelOrReturn(step, wIdx, goingRight, length)
    placeTorchIfNeeded(step, wIdx)
    status(step, wIdx, goingRight, length); pausePoint()
  end
end

local function mineFrom(startStep, startWIdx, startDirRight, length, resumeMode)
  local goingRight = startDirRight
  local step = startStep

  if resumeMode then
    clearColumn()
    maybeAutoReturn(step, startWIdx, goingRight, length)
    ensureFuelOrReturn(step, startWIdx, goingRight, length)
    placeTorchIfNeeded(step, startWIdx)
    status(step, startWIdx, goingRight, length); pausePoint()
    for col = startWIdx+1, WIDTH do
      if goingRight then moveRight() else moveLeft() end
      clearColumn()
      maybeAutoReturn(step, col, goingRight, length)
      ensureFuelOrReturn(step, col, goingRight, length)
      placeTorchIfNeeded(step, col)
      status(step, col, goingRight, length); pausePoint()
    end
    goingRight = not goingRight
    step = step + 1
  end

  for s=step, length do
    if ABORT then break end
    ensureForward()
    doSlice(s, goingRight, length)
    goingRight = not goingRight
  end

  if goingRight == false then for i=1, WIDTH-1 do moveLeft() end end
  turtle.turnLeft(); turtle.turnLeft()
  for i=1, (resumeMode and (step-1) or length) do ensureForward() end
  dumpToChestBehind()                           -- finaler Dump: Ruecken zur Kiste
  if ABORT then say("Abgebrochen & entladen.") else say("Fertig & entladen.") end
end

local function mineMain()
  term.clear(); term.setCursorPos(1,1)
  say("Tunnel-Mode ON (Ender, Status, Chat+Log)")

  io.write(de("Wie lang soll der Tunnel sein (Bloecke)? ") )
  local LENGTH = tonumber(read() or "0") or 0
  if LENGTH<=0 then say("Ungueltige Laenge"); return end

  say("Fuel-Empfehlung ca. %d", estimateTotalFuel(LENGTH))
  refuelAll()

  if rednet.isOpen() then
    rednet.broadcast({
      type="status", name=(CFG.name or "turtle"), step=0, length=LENGTH, col=1, width=WIDTH,
      dir="right", fuel=turtle.getFuelLevel(), needHome=0, slotsFree=slotsFree(), ts=os.time()
    },"turtleStatus")
    sendLog(0,1,true,LENGTH)
  end

  local st = loadState()
  if st and st.length == LENGTH then
    io.write(de("Resume gefunden. Fortsetzen (j/N)? "))
    local ans = string.lower(read() or "")
    if ans=="j" or ans=="ja" then
      for i=1, st.step-1 do ensureForward() end
      for i=1, (st.wIdx-1) do moveRight() end
      clearState()
      mineFrom(st.step, st.wIdx, st.goingRight, LENGTH, true)
      return
    else
      clearState()
    end
  end

  ensureForward()
  doSlice(1, true, LENGTH)
  mineFrom(2, 1, false, LENGTH, false)
end

parallel.waitForAny(controlListener, mineMain)
