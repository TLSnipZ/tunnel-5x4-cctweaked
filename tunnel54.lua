-- tunnel54.lua
-- 5 breit (rechts), 4 hoch, Länge per Prompt.
-- Start: Turtle steht links unten, guckt in den Tunnel. Truhe steht HINTER ihr.
-- Features: Auto-Refuel, Auto-Return bei vollem Inventar, dynamischer Fuel-Check,
-- Resume nach Crash, Home-Unload + Refuel aus Truhe.

local WIDTH  = 5
local HEIGHT = 4
local STATE_FILE = "tunnel54.state"

-- ==== Utils ====
local function refuelAll()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then turtle.refuel(64) end
  end
  turtle.select(1)
end

local function ensureForward()
  while turtle.detect() do turtle.dig(); sleep(0.05) end
  while not turtle.forward() do turtle.attack(); turtle.dig(); sleep(0.05) end
end

local function ensureUp()
  while turtle.detectUp() do turtle.digUp(); sleep(0.05) end
  while not turtle.up() do turtle.attackUp(); turtle.digUp(); sleep(0.05) end
end

local function ensureDown()
  while not turtle.down() do turtle.attackDown(); turtle.digDown(); sleep(0.05) end
end

local function moveRight()
  turtle.turnRight()
  ensureForward()
  turtle.turnLeft()
end

local function moveLeft()
  turtle.turnLeft()
  ensureForward()
  turtle.turnRight()
end

local function dumpToChestBehind()
  -- Truhe ist hinter der ursprünglichen Start-Ausrichtung
  turtle.turnLeft(); turtle.turnLeft()
  for slot = 1, 16 do
    turtle.select(slot); turtle.drop()
  end
  turtle.select(1)
  turtle.turnLeft(); turtle.turnLeft()
end

local function invFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

-- ==== State (Resume) ====
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

local function clearState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

-- ==== Fuel-Helpers ====
local function distanceToLeft(wIdx, goingRight)
  -- Wie viele Schritte bis zur linken Kante dieser Scheibe?
  if goingRight then
    return (wIdx - 1)
  else
    return (WIDTH - wIdx)
  end
end

local function refuelFromChestFront()
  -- Erwartung: Truhe ist VOR der Turtle (am Start).
  -- 1) Versuche mehrfach Items zu saugen
  for i = 1, 8 do turtle.suck(64) end
  -- 2) Alles Brennbare verbrennen
  refuelAll()
  -- 3) Rest wieder zurücklegen (Slots leeren)
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.drop() end
  end
  turtle.select(1)
end

-- Rückweg + Entladen + Refuel + Rückkehr an Arbeitsstelle
local function goHomeUnloadAndReturn(step, wIdx, goingRight)
  -- 1) Zur linken Kante dieser Scheibe
  local leftMoves = distanceToLeft(wIdx, goingRight)
  for i = 1, leftMoves do moveLeft() end

  -- 2) 180° + step Blöcke "vor" (real zurück) bis Start
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  -- 3) Entladen in Truhe (Truhe ist jetzt VOR uns)
  for slot = 1, 16 do
    turtle.select(slot); turtle.drop()
  end
  turtle.select(1)

  -- 3b) Sprit aus Truhe ziehen & betanken (falls vorhanden)
  refuelFromChestFront()

  -- 4) Zurück zur Scheibe
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  -- 5) Von links zur gespeicherten wIdx zurück
  for i = 1, (wIdx - 1) do moveRight() end
end

-- Eine Spalte (unten->oben->unten) räumen
local function clearColumn(height)
  -- rauf
  for i = 1, height - 1 do
    ensureUp()
  end
  -- runter
  for i = 1, height - 1 do
    ensureDown()
  end
end

local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    saveState(step, wIdx, goingRight, length)
    goHomeUnloadAndReturn(step, wIdx, goingRight)
    clearState()
  end
end

local function ensureFuelOrReturn(step, wIdx, goingRight, length)
  -- Mindesttreibstoff, um JETZT sicher heimzukommen:
  -- bis zur linken Kante + 'step' nach "vorne" (real zurück) + kleine Reserve
  local reserve = 5
  local needHome = distanceToLeft(wIdx, goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  if lvl ~= "unlimited" and lvl < needHome then
    print("Fuel knapp -> Heimkehr & Refuel...")
    saveState(step, wIdx, goingRight, length)
    goHomeUnloadAndReturn(step, wIdx, goingRight)
    clearState()
  end
end

-- ==== Start / Input ====
term.clear(); term.setCursorPos(1,1)
print("5x4 Tunnelgraber (Auto-Return + Auto-Refuel)")
io.write("Wie lang soll der Tunnel sein (Bloecke)? ")
local LENGTH = tonumber(read() or "0") or 0
if LENGTH <= 0 then print("Ungueltige Laenge."); return end

-- Erstes Refuel (falls Fuel schon im Inventar)
refuelAll()

-- Resume anbieten
local resume = loadState()
if resume and resume.length == LENGTH then
  print("Gefundener Speicherstand. Resume? (j/N)")
  local ans = string.lower(read() or "")
  if ans == "j" or ans == "ja" then
    for i = 1, resume.step do ensureForward() end
    for i = 1, (resume.wIdx - 1) do moveRight() end
    clearState()

    local stepStart = resume.step
    local goingRight = resume.goingRight

    -- aktuelle Spalte fertig
    clearColumn(HEIGHT)
    maybeAutoReturn(stepStart, resume.wIdx, goingRight, LENGTH)
    ensureFuelOrReturn(stepStart, resume.wIdx, goingRight, LENGTH)

    -- Restliche Spalten dieser Scheibe
    for col = resume.wIdx + 1, WIDTH do
      if goingRight then moveRight() else moveLeft() end
      clearColumn(HEIGHT)
      maybeAutoReturn(stepStart, col, goingRight, LENGTH)
      ensureFuelOrReturn(stepStart, col, goingRight, LENGTH)
    end

    -- Restliche Scheiben
    local going = not goingRight
    for step = stepStart + 1, LENGTH do
      ensureForward()
      clearColumn(HEIGHT)
      maybeAutoReturn(step, 1, going, LENGTH)
      ensureFuelOrReturn(step, 1, going, LENGTH)
      for col = 2, WIDTH do
        if going then moveRight() else moveLeft() end
        clearColumn(HEIGHT)
        maybeAutoReturn(step, col, going, LENGTH)
        ensureFuelOrReturn(step, col, going, LENGTH)
      end
      going = not going
    end

    -- Ende: nach links angleichen, heim + entladen
    if not going then
      for i = 1, WIDTH - 1 do moveLeft() end
    end
    turtle.turnLeft(); turtle.turnLeft()
    for i = 1, LENGTH do ensureForward() end
    dumpToChestBehind()
    print("Fertig mit Resume + Fuel-Check.")
    return
  else
    clearState()
  end
end

-- ==== Frischer Run ====
local goingRight = true

for step = 1, LENGTH do
  ensureForward()
  -- Spalte 1
  clearColumn(HEIGHT)
  maybeAutoReturn(step, 1, goingRight, LENGTH)
  ensureFuelOrReturn(step, 1, goingRight, LENGTH)

  -- Restliche Spalten
  for wIdx = 2, WIDTH do
    if goingRight then moveRight() else moveLeft() end
    clearColumn(HEIGHT)
    maybeAutoReturn(step, wIdx, goingRight, LENGTH)
    ensureFuelOrReturn(step, wIdx, goingRight, LENGTH)
  end

  goingRight = not goingRight
end

-- Am Ende ggf. von rechts nach links rüber
if goingRight == false then
  for i = 1, WIDTH - 1 do moveLeft() end
end

-- Heim + Entladen
turtle.turnLeft(); turtle.turnLeft()
for i = 1, LENGTH do ensureForward() end
dumpToChestBehind()
print("Fertig! 5x4-Tunnel gegraben, Fuel überwacht, entladen.")
