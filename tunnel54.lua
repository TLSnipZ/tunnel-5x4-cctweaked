-- tunnel54.lua (ASCII output)
-- 5x4 Tunnel mit Auto-Return (Inventar + Fuel), Auto-Refuel, Auto-Fackeln (mittig unten, alle 6),
-- Torch-Schutz (Fackeln nicht abbauen), Resume-Telemetrie, Fun-Quotes, Rednet Broadcast.
-- Alle Ausgaben werden auf ASCII normalisiert (ae/oe/ue/ss).

-- ===== Konfiguration =====
local WIDTH          = 5
local HEIGHT         = 4
local STATE_FILE     = "tunnel54.state"
local VERBOSE        = true
local TORCH_INTERVAL = 6                 -- alle 6 Steps
local TORCH_NAME     = "minecraft:torch" -- Item-Name fuer Fackeln
local TURTLE_MODEM   = "right"           -- Seite des Wireless Modems an der Turtle

-- Fuel Konstanten (typische CC:Tweaked Defaults)
local FUEL_COAL       = 80
local FUEL_COAL_BLOCK = 720
local FUEL_LAVA       = 1000

-- Fun Quotes (ASCII only)
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
  "Arbeiten ohne Musik? Stell mir wenigstens Spotify rein",
  "Ohne Fackeln ist es hier trueb wie Montagmorgen",
  "Kohle tanken ist mein Energy-Drink",
  "Tunnel gerade wie ne Tuning-Achse (hoffentlich)",
  "Ich bau dir Minecraft-Autobahnen",
  "Ich setz dir mehr Fackeln als du Likes hast",
  "Mission Mining Impossible",
}

-- ===== Helpers: ASCII Normalisierung & Output =====
local function deUmlaut(s)
  s = s:gsub("Ä","Ae"):gsub("Ö","Oe"):gsub("Ü","Ue")
  s = s:gsub("ä","ae"):gsub("ö","oe"):gsub("ü","ue"):gsub("ß","ss")
  return s
end

local function say(fmt, ...)
  local msg = string.format(fmt, ...)
  msg = deUmlaut(msg)
  print("🐢 "..msg)
  if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
end

local function randomChat()
  if not VERBOSE then return end
  if math.random(1, 10) == 1 then
    local msg = randomQuotes[math.random(1, #randomQuotes)]
    msg = deUmlaut(msg)
    print("🐢 "..msg)
    if rednet.isOpen() then rednet.broadcast("🐢 "..msg, "turtleChat") end
  end
end

-- ===== Bewegungs-/Interaktions-Utils =====
local function refuelAll()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then turtle.refuel(64) end
  end
  turtle.select(1)
end

-- Vorwaerts mit Torch-Schutz (Fackeln nicht abbauen)
local function ensureForward()
  while turtle.detect() do
    local ok, data = turtle.inspect()
    if ok and data and data.name == TORCH_NAME then
      if turtle.forward() then return end
    else
      turtle.dig(); sleep(0.05)
    end
  end
  while not turtle.forward() do
    turtle.attack(); turtle.dig(); sleep(0.05)
  end
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
  for slot = 1, 16 do turtle.select(slot); turtle.drop() end
  turtle.select(1)
  turtle.turnLeft(); turtle.turnLeft()
end

local function invFull()
  for slot = 1, 16 do if turtle.getItemCount(slot) == 0 then return false end end
  return true
end

local function slotsFree()
  local free = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then free = free + 1 end end
  return free
end

local function estimateTotalFuel(length) return length * 35 + length + 100 end

-- ===== State (Resume) =====
local function saveState(step, wIdx, goingRight, length)
  local h = fs.open(STATE_FILE, "w")
  h.write(textutils.serialize({step=step, wIdx=wIdx, goingRight=goingRight, length=length}))
  h.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return nil end
  local h = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(h.readAll())
  h.close()
  return t
end

local function clearState() if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end end

-- ===== Fuel & Return =====
local function distanceToLeft(wIdx, goingRight)
  if goingRight then return (wIdx - 1) else return (WIDTH - wIdx) end
end

local function refuelFromChestFront()
  for i = 1, 8 do turtle.suck(64) end
  refuelAll()
  -- Reste zurueck
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.drop() end
  end
  turtle.select(1)
end

local function takeTorchesFromChest()
  for i = 1, 8 do turtle.suck(64) end
end

local function goHomeUnloadAndReturn(step, wIdx, goingRight)
  -- zur linken Kante der aktuellen Scheibe
  local leftMoves = distanceToLeft(wIdx, goingRight)
  for i = 1, leftMoves do moveLeft() end
  -- 180° und step Schritte "vor" (real zurueck) zum Start
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  say("Back @ Home - Loot droppen")
  for slot = 1, 16 do turtle.select(slot); turtle.drop() end
  turtle.select(1)

  say("Check Sprit & Fackeln in der Kiste")
  refuelFromChestFront()
  takeTorchesFromChest()

  -- zurueck zur Arbeitsstelle
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end
  for i = 1, (wIdx - 1) do moveRight() end
  say("Zurueck am Arbeitsplatz")
end

local function clearColumn(height)
  for i = 1, height - 1 do ensureUp() end
  for i = 1, height - 1 do ensureDown() end
end

local function placeTorchIfNeeded(step, wIdx)
  if step % TORCH_INTERVAL == 0 and wIdx == 3 then
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail and detail.name == TORCH_NAME then
        turtle.select(slot)
        turtle.placeDown()
        say("Fackel gesetzt (Step %d)", step)
        return
      end
    end
  end
end

-- Strukturierter Status für GUI + Chat-Status
local function status(step, wIdx, goingRight, length)
  local reserve = 5
  local needHome = distanceToLeft(wIdx, goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()

  if VERBOSE then
    say("[Step %d/%d | Col %d/%d] Fuel: %s | Heim min: %d | Slots frei: %d",
      step, length, wIdx, WIDTH, tostring(lvl), needHome, slotsFree())
    randomChat()
  end

  local data = {
    type="status",
    step=step, length=length,
    col=wIdx, width=WIDTH,
    dir=(goingRight and "right" or "left"),
    fuel=lvl,
    needHome=needHome,
    slotsFree=slotsFree(),
    ts=os.time()
  }
  if rednet.isOpen() then rednet.broadcast(data, "turtleStatus") end
end

local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    say("Inventar voll -> Heimweg")
    saveState(step, wIdx, goingRight, length)
    goHomeUnloadAndReturn(step, wIdx, goingRight)
    clearState()
  end
end

local function ensureFuelOrReturn(step, wIdx, goingRight, length)
  local reserve = 5
  local needHome = distanceToLeft(wIdx, goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  if lvl ~= "unlimited" and lvl < needHome then
    say("Fuel low -> Retreat")
    saveState(step, wIdx, goingRight, length)
    goHomeUnloadAndReturn(step, wIdx, goingRight)
    clearState()
  end
end

-- ===== Main =====
term.clear(); term.setCursorPos(1,1)
rednet.open(TURTLE_MODEM)  -- Modem-Seite
say("Tunnel-Mode ON (Fackeln, Auto-Return, Broadcast)")

io.write("Wie lang soll der Tunnel sein (Bloecke)? ")
local LENGTH = tonumber(read() or "0") or 0
if LENGTH <= 0 then say("Ungueltige Laenge"); return end

local est = estimateTotalFuel(LENGTH)
say("Empfehlung Fuel grob: %d", est)

refuelAll()

local goingRight = true
for step = 1, LENGTH do
  ensureForward()
  clearColumn(HEIGHT)
  maybeAutoReturn(step, 1, goingRight, LENGTH)
  ensureFuelOrReturn(step, 1, goingRight, LENGTH)
  placeTorchIfNeeded(step, 1)
  status(step, 1, goingRight, LENGTH)

  for wIdx = 2, WIDTH do
    if goingRight then moveRight() else moveLeft() end
    clearColumn(HEIGHT)
    maybeAutoReturn(step, wIdx, goingRight, LENGTH)
    ensureFuelOrReturn(step, wIdx, goingRight, LENGTH)
    placeTorchIfNeeded(step, wIdx)
    status(step, wIdx, goingRight, LENGTH)
  end
  goingRight = not goingRight
end

-- Am Ende ggf. von rechts nach links rueber
if goingRight == false then for i = 1, WIDTH - 1 do moveLeft() end end
-- Heim + Entladen
turtle.turnLeft(); turtle.turnLeft()
for i = 1, LENGTH do ensureForward() end
dumpToChestBehind()
say("Tunnel abgeschlossen - Loot & Licht ready")
