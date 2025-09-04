-- tunnel54.lua (ASCII + Control + GUI-Telemetrie)
-- 5x4 Tunnel; Auto-Return (Inventar/Fuel), Auto-Refuel, Fackeln (mittig unten, alle 6),
-- Torch-Schutz, Resume nach Unterbrechung, Live-Status+Chat via Rednet,
-- Fernsteuerung: Pause/Resume/Stop/Verbose über turtleControl-Protokoll.

-- ===== Konfiguration =====
local WIDTH, HEIGHT      = 5, 4
local TORCH_INTERVAL     = 6                 -- alle 6 Steps
local TORCH_NAME         = "minecraft:torch" -- Fackel-Itemname
local STATE_FILE         = "tunnel54.state"
local TURTLE_MODEM_SIDE  = "right"           -- Modem an Turtle
local VERBOSE            = true              -- Chat-Output an/aus

-- Typische CC:Tweaked Fuelwerte
local FUEL_COAL, FUEL_COAL_BLOCK, FUEL_LAVA = 80, 720, 1000

-- ===== Control-Flags (Fernsteuerung) =====
local PAUSED, ABORT = false, false

-- ===== ASCII (Umlaute -> ae/oe/ue/ss) =====
local function deUmlaut(s)
  s = s:gsub("Ä","Ae"):gsub("Ö","Oe"):gsub("Ü","Ue")
  s = s:gsub("ä","ae"):gsub("ö","oe"):gsub("ü","ue"):gsub("ß","ss")
  return s
end

-- ===== Output =====
local function say(fmt, ...)
  local msg = deUmlaut(string.format(fmt, ...))
  print("🐢 "..msg)
  if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
end

local randomQuotes = {
  "Brudi, hier unten ist es dunkler als in meiner Zukunft :D",
  "Stein um Stein... fuehl mich wie Bob der Baumeister",
  "Warum grabe ich eigentlich und nicht du?",
  "Wenn hier Lava kommt, geb ich dir die Schuld",
  "Slots platzen gleich wie mein Terminkalender",
  "Bro, ich schwitz mehr als du aufm Festival",
  "Mining-Turtle: 1, Kies: 0",
  "Tunnel-Business laeuft stabil",
  "Hab Bock auf nen Doener nach Schichtende",
  "Arbeiten ohne Musik? Stell mir Spotify rein",
  "Ohne Fackeln ist es hier trueb wie Montagmorgen",
  "Kohle tanken ist mein Energy-Drink",
  "Ich bau dir Minecraft-Autobahnen",
  "Ich setz dir mehr Fackeln als du Likes hast",
  "Mission Mining Impossible",
}
local function randomChat()
  if not VERBOSE then return end
  if math.random(1,10)==1 then
    local msg = deUmlaut(randomQuotes[math.random(1,#randomQuotes)])
    print("🐢 "..msg)
    if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
  end
end

-- ===== Bewegungs-/Interaktions-Utils =====
local function refuelAll()
  for s=1,16 do turtle.select(s); if turtle.refuel(0) then turtle.refuel(64) end end
  turtle.select(1)
end

-- Vorwärts mit Torch-Schutz (Fackeln nicht abbauen)
local function ensureForward()
  while turtle.detect() do
    local ok, data = turtle.inspect()
    if ok and data and data.name == TORCH_NAME then
      if turtle.forward() then return end
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

local function dumpToChestBehind()
  turtle.turnLeft(); turtle.turnLeft()
  for s=1,16 do turtle.select(s); turtle.drop() end
  turtle.select(1); turtle.turnLeft(); turtle.turnLeft()
end

local function invFull()
  for s=1,16 do if turtle.getItemCount(s)==0 then return false end end
  return true
end

local function slotsFree()
  local f=0; for s=1,16 do if turtle.getItemCount(s)==0 then f=f+1 end end; return f
end

local function estimateTotalFuel(len) return len*35 + len + 100 end

-- ===== State (Resume) =====
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

-- ===== Fuel & Return =====
local function distanceToLeft(wIdx, goingRight)
  if goingRight then return (wIdx-1) else return (WIDTH - wIdx) end
end

local function refuelFromChestFront()
  for i=1,8 do turtle.suck(64) end
  refuelAll()
  for s=1,16 do turtle.select(s); if turtle.getItemCount(s)>0 then turtle.drop() end end
  turtle.select(1)
end

local function takeTorchesFromChest()
  for i=1,8 do turtle.suck(64) end
end

local function goHomeUnloadAndReturn(step, wIdx, goingRight)
  for i=1, distanceToLeft(wIdx,goingRight) do moveLeft() end
  turtle.turnLeft(); turtle.turnLeft()
  for i=1, step do ensureForward() end

  say("Back @ Home - Loot droppen")
  for s=1,16 do turtle.select(s); turtle.drop() end
  turtle.select(1)

  say("Check Sprit & Fackeln in der Kiste")
  refuelFromChestFront()
  takeTorchesFromChest()

  turtle.turnLeft(); turtle.turnLeft()
  for i=1, step do ensureForward() end
  for i=1, (wIdx-1) do moveRight() end
  say("Zurueck am Arbeitsplatz")
end

local function clearColumn(hh)
  for i=1, hh-1 do ensureUp() end
  for i=1, hh-1 do ensureDown() end
end

local function placeTorchIfNeeded(step, wIdx)
  if step % TORCH_INTERVAL == 0 and wIdx == 3 then
    for s=1,16 do
      local d=turtle.getItemDetail(s)
      if d and d.name==TORCH_NAME then
        turtle.select(s); turtle.placeDown(); say("Fackel gesetzt (Step %d)", step); return
      end
    end
  end
end

-- ===== Telemetrie + Status =====
local function status(step, wIdx, goingRight, length)
  local reserve=5
  local needHome = distanceToLeft(wIdx,goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()

  if VERBOSE then
    say("[Step %d/%d | Col %d/%d] Fuel: %s | Heim min: %d | Slots frei: %d",
      step,length,wIdx,WIDTH,tostring(lvl),needHome,slotsFree())
    randomChat()
  end

  local data = {
    type="status",
    step=step, length=length,
    col=wIdx, width=WIDTH,
    dir=(goingRight and "right" or "left"),
    fuel=lvl, needHome=needHome,
    slotsFree=slotsFree(), ts=os.time()
  }
  if rednet.isOpen() then rednet.broadcast(data,"turtleStatus") end
end

-- ===== Auto-Return Checks =====
local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    say("Inventar voll -> Heimweg")
    saveState(step,wIdx,goingRight,length)
    goHomeUnloadAndReturn(step,wIdx,goingRight)
    clearState()
  end
end

local function ensureFuelOrReturn(step, wIdx, goingRight, length)
  local reserve=5
  local needHome = distanceToLeft(wIdx,goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  if lvl~="unlimited" and lvl < needHome then
    say("Fuel low -> Retreat")
    saveState(step,wIdx,goingRight,length)
    goHomeUnloadAndReturn(step,wIdx,goingRight)
    clearState()
  end
end

-- ===== Fernsteuerung (Listener) =====
local function controlListener()
  while true do
    local id,msg,proto = rednet.receive("turtleControl")
    if type(msg)=="string" then msg = msg:lower() end
    if msg=="pause"   then PAUSED=true;  say("Pause aktiviert") end
    if msg=="resume"  then PAUSED=false; say("Weiter gehts") end
    if msg=="stop"    then ABORT=true;   say("Stop angefordert") end
    if msg=="verbose" then VERBOSE=not VERBOSE; say("Verbose = %s", tostring(VERBOSE)) end
  end
end

local function pausePoint()
  while PAUSED and not ABORT do sleep(0.2) end
end

-- ===== Mining-Logik (mit optionalem Resume) =====
local function doSlice(step, goingRight, length)
  clearColumn(HEIGHT)
  maybeAutoReturn(step, 1, goingRight, length)
  ensureFuelOrReturn(step, 1, goingRight, length)
  placeTorchIfNeeded(step, 1)
  status(step, 1, goingRight, length); pausePoint()

  for wIdx=2, WIDTH do
    if goingRight then moveRight() else moveLeft() end
    clearColumn(HEIGHT)
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
    -- Wir stehen bereits an der gespeicherten Spalte (hin-navigiert in mineMain)
    -- 1) aktuelle Spalte fertig
    clearColumn(HEIGHT)
    maybeAutoReturn(step, startWIdx, goingRight, length)
    ensureFuelOrReturn(step, startWIdx, goingRight, length)
    placeTorchIfNeeded(step, startWIdx)
    status(step, startWIdx, goingRight, length); pausePoint()
    -- 2) Rest der Breite
    for col = startWIdx+1, WIDTH do
      if goingRight then moveRight() else moveLeft() end
      clearColumn(HEIGHT)
      maybeAutoReturn(step, col, goingRight, length)
      ensureFuelOrReturn(step, col, goingRight, length)
      placeTorchIfNeeded(step, col)
      status(step, col, goingRight, length); pausePoint()
    end
    -- 3) Nächste Scheibe ab hier normal
    goingRight = not goingRight
    step = step + 1
  end

  for s = step, length do
    if ABORT then break end
    ensureForward()
    doSlice(s, goingRight, length)
    goingRight = not goingRight
  end

  -- Ende / Abbruch: zur linken Kante angleichen
  if goingRight == false then for i=1, WIDTH-1 do moveLeft() end end
  -- Heim + entladen
  turtle.turnLeft(); turtle.turnLeft()
  for i=1, (resumeMode and (step-1) or length) do ensureForward() end
  dumpToChestBehind()
  if ABORT then say("Job abgebrochen & sicher beendet") else say("Tunnel abgeschlossen - Loot & Licht ready") end
end

local function mineMain()
  term.clear(); term.setCursorPos(1,1)
  rednet.open(TURTLE_MODEM_SIDE)
  say("Tunnel-Mode ON (Fackeln, Auto-Return, Broadcast)")

  io.write("Wie lang soll der Tunnel sein (Bloecke)? ")
  local LENGTH = tonumber(read() or "0") or 0
  if LENGTH<=0 then say("Ungueltige Laenge"); return end

  say("Empfehlung Fuel grob: %d", estimateTotalFuel(LENGTH))
  refuelAll()

  -- Resume?
  local st = loadState()
  if st and st.length == LENGTH then
    say("Resume gefunden. (j/N)?")
    local ans = string.lower(read() or "")
    if ans=="j" or ans=="ja" then
      -- Vom Start bis zur Scheibe vorruecken
      for i=1, st.step-1 do ensureForward() end
      -- zur linken Kante stehen wir bereits; nun zur wIdx
      for i=1, (st.wIdx-1) do moveRight() end
      clearState()
      mineFrom(st.step, st.wIdx, st.goingRight, LENGTH, true)
      return
    else
      clearState()
    end
  end

  -- Frischer Run
  for i=1,1 do end -- no-op
  ensureForward() -- in die erste Scheibe rein
  doSlice(1, true, LENGTH)
  mineFrom(2, 1, false, LENGTH, false)
end

-- ===== Parallel: Listener + Mining =====
parallel.waitForAny(controlListener, mineMain)
