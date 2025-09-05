-- tunnel54.lua
-- 5x4 Tunnel Miner mit Ender-Modem (unendliche Range), Auto-Return, Torches,
-- Resume, Live-Status, gezielte Fernsteuerung via rednet.host("turtleCtl", <name>).
-- ASCII-only (ae/oe/ue/ss). For CC:Tweaked.

-- ====== Config ======
local WIDTH, HEIGHT = 5, 4
local TORCH_INTERVAL = 6
local TORCH_NAME = "minecraft:torch"
local STATE_FILE = "tunnel54.state"
local CFG_FILE   = "tunnel54.cfg"
local VERBOSE = true

-- ====== Utils (ASCII + IO) ======
local function de(s)
  s = s:gsub("Ä","Ae"):gsub("Ö","Oe"):gsub("Ü","Ue")
  s = s:gsub("ä","ae"):gsub("ö","oe"):gsub("ü","ue"):gsub("ß","ss")
  return s
end
local function say(fmt, ...)
  local msg = de(string.format(fmt, ...))
  print("🐢 "..msg)
  if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
end

-- ====== Ender-Modem: alle Modems oeffnen ======
local function openAnyModems()
  for _,side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      pcall(rednet.open, side)
    end
  end
end
openAnyModems()

-- ====== Config laden/speichern (Name + evtl. Defaults) ======
local CFG = {}
local function loadCfg()
  if fs.exists(CFG_FILE) then
    local h=fs.open(CFG_FILE,"r"); CFG = textutils.unserialize(h.readAll()) or {}; h.close()
  end
end
local function saveCfg() local h=fs.open(CFG_FILE,"w"); h.write(textutils.serialize(CFG)); h.close() end
loadCfg()
if not CFG.name then
  term.setCursorPos(1,1); term.clear()
  print("Turtle-Name eingeben (z.B. alpha/beta):")
  CFG.name = read()
  saveCfg()
end

-- Turtle unter ihrem Namen als Control-Host anmelden
if rednet.isOpen() then
  pcall(rednet.host, "turtleCtl", CFG.name)
end

-- ====== Movement / Mining ======
local function refuelAll()
  for s=1,16 do turtle.select(s); if turtle.refuel(0) then turtle.refuel(64) end end
  turtle.select(1)
end
local function ensureForward()
  while turtle.detect() do
    local ok, data = turtle.inspect()
    if ok and data and data.name == TORCH_NAME then
      break -- Torch nicht abbauen, ggf. davor stehen bleiben
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

local function invFull()
  for s=1,16 do if turtle.getItemCount(s)==0 then return false end end
  return true
end
local function slotsFree()
  local f=0; for s=1,16 do if turtle.getItemCount(s)==0 then f=f+1 end end; return f
end

local function dumpToChestBehind()
  turtle.turnLeft(); turtle.turnLeft()
  for s=1,16 do turtle.select(s); turtle.drop() end
  turtle.select(1); turtle.turnLeft(); turtle.turnLeft()
end

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

-- ====== Status + Telemetrie ======
local function distanceToLeft(wIdx, goingRight)
  if goingRight then return (wIdx-1) else return (WIDTH - wIdx) end
end
local function status(step, wIdx, goingRight, length)
  local reserve=5
  local needHome = distanceToLeft(wIdx,goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  if VERBOSE then
    say("[%s] Step %d/%d | Col %d/%d | Fuel %s | Heim %d | Frei %d",
      CFG.name, step,length,wIdx,WIDTH,tostring(lvl),needHome,slotsFree())
  end
  local data = {
    type="status", name=CFG.name,
    step=step, length=length, col=wIdx, width=WIDTH,
    dir=(goingRight and "right" or "left"),
    fuel=lvl, needHome=needHome, slotsFree=slotsFree(), ts=os.time()
  }
  if rednet.isOpen() then rednet.broadcast(data, "turtleStatus") end
end

-- ====== Torches ======
local function placeTorchIfNeeded(step, wIdx)
  if step % TORCH_INTERVAL == 0 and wIdx == 3 then
    for s=1,16 do
      local d=turtle.getItemDetail(s)
      if d and d.name==TORCH_NAME then
        turtle.select(s); turtle.placeDown(); say("[%s] Fackel gesetzt @ step %d", CFG.name, step); turtle.select(1); return
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
    say("[%s] Fuel low -> Heimweg", CFG.name)
    saveState(step,wIdx,goingRight,length)
    -- zur linken Kante der aktuellen Scheibe
    for i=1, distanceToLeft(wIdx,goingRight) do moveLeft() end
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    say("[%s] @Home - droppen & refuel", CFG.name)
    dumpToChestBehind()
    -- Fuel aus Kiste ziehen
    for i=1,8 do turtle.suck(64) end
    refuelAll()
    for s=1,16 do turtle.select(s); if turtle.getItemCount(s)>0 then turtle.drop() end end
    turtle.select(1)
    -- zur Stelle zurueck
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    for i=1, (wIdx-1) do moveRight() end
    clearState()
  end
end

local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    say("[%s] Inventar voll -> Heimweg", CFG.name)
    saveState(step,wIdx,goingRight,length)
    -- zur linken Kante
    for i=1, distanceToLeft(wIdx,goingRight) do moveLeft() end
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    say("[%s] @Home - droppen", CFG.name)
    dumpToChestBehind()
    -- ggf. refuel versuchen
    for i=1,8 do turtle.suck(64) end
    refuelAll()
    for s=1,16 do turtle.select(s); if turtle.getItemCount(s)>0 then turtle.drop() end end
    turtle.select(1)
    -- zur Stelle
    turtle.turnLeft(); turtle.turnLeft()
    for i=1, step do ensureForward() end
    for i=1, (wIdx-1) do moveRight() end
    clearState()
  end
end

-- ====== Clear Column ======
local function clearColumn()
  for i=1, HEIGHT-1 do ensureUp() end
  for i=1, HEIGHT-1 do ensureDown() end
end

-- ====== Control (Pause/Resume/Stop/Verbose) ======
local PAUSED, ABORT = false, false
local function controlListener()
  while true do
    local id, msg, proto = rednet.receive("turtleCtl")
    -- Wir akzeptieren: direkte Send (ID gezielt) ODER broadcast mit table {target=CFG.name, cmd=...}
    local cmd = nil
    if type(msg)=="string" then cmd = msg:lower()
    elseif type(msg)=="table" then
      if msg.target and msg.target ~= CFG.name then
        -- nicht fuer uns
      else
        cmd = (msg.cmd or ""):lower()
      end
    end
    if cmd=="pause"   then PAUSED=true;  say("[%s] Pause", CFG.name) end
    if cmd=="resume"  then PAUSED=false; say("[%s] Weiter", CFG.name) end
    if cmd=="stop"    then ABORT=true;   say("[%s] Stop angefordert", CFG.name) end
    if cmd=="verbose" then VERBOSE=not VERBOSE; say("[%s] Verbose=%s", CFG.name, tostring(VERBOSE)) end
  end
end
local function pausePoint() while PAUSED and not ABORT do sleep(0.2) end end

-- ====== Work Steps ======
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
    -- aktuelle Spalte fertig
    clearColumn()
    maybeAutoReturn(step, startWIdx, goingRight, length)
    ensureFuelOrReturn(step, startWIdx, goingRight, length)
    placeTorchIfNeeded(step, startWIdx)
    status(step, startWIdx, goingRight, length); pausePoint()
    -- Rest der Breite
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

  -- links ausrichten
  if goingRight == false then for i=1, WIDTH-1 do moveLeft() end end
  -- heim
  turtle.turnLeft(); turtle.turnLeft()
  for i=1, (resumeMode and (step-1) or length) do ensureForward() end
  dumpToChestBehind()
  if ABORT then say("[%s] Abgebrochen & entladen.", CFG.name) else say("[%s] Fertig & entladen.", CFG.name) end
end

local function mineMain()
  term.clear(); term.setCursorPos(1,1)
  say("[%s] Tunnel-Mode ON (Ender-Modem, Broadcast, Control)", CFG.name)

  io.write(de("Wie lang soll der Tunnel sein (Bloecke)? ") )
  local LENGTH = tonumber(read() or "0") or 0
  if LENGTH<=0 then say("[%s] Ungueltige Laenge", CFG.name); return end

  say("[%s] Fuel-Empfehlung ca. %d", CFG.name, estimateTotalFuel(LENGTH))
  refuelAll()

  -- Heartbeat-Status direkt senden
  if rednet.isOpen() then
    rednet.broadcast({
      type="status", name=CFG.name, step=0, length=LENGTH, col=1, width=WIDTH,
      dir="right", fuel=turtle.getFuelLevel(), needHome=0, slotsFree=slotsFree(), ts=os.time()
    },"turtleStatus")
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

  -- Fresh run
  ensureForward()
  doSlice(1, true, LENGTH)
  mineFrom(2, 1, false, LENGTH, false)
end

parallel.waitForAny(controlListener, mineMain)
