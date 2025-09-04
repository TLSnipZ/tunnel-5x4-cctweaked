-- tunnel54.lua
-- 5 breit (rechts), 4 hoch, Länge per Prompt.
-- Start: Turtle steht links unten, guckt in den Tunnel. Truhe steht HINTER ihr.
-- Features: Auto-Refuel, Auto-Return bei vollem Inventar, Resume an gleicher Stelle.

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

local function needFuelFor(len)
  -- grobe Hausnummer inkl. Rückwege
  return len * 35 + len + 50
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
  -- Truhe ist hinter der ursprünglichen Start-Orientierung.
  -- Wir drehen uns um, droppen vorwärts, drehen zurück.
  turtle.turnLeft(); turtle.turnLeft()
  for slot = 1, 16 do
    turtle.select(slot)
    turtle.drop()
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
-- Wir speichern: step (1..LENGTH), wIdx (1..WIDTH), goingRight (bool)
-- Bedeutungen:
-- - step = Index der "Scheibe" entlang der Länge, in der wir uns befinden (wir sind bereits 1 Block vorgerückt).
-- - wIdx = aktuelle Spalten-Position (1 = ganz links)
-- - goingRight = aktuelle Sweep-Richtung innerhalb der Breite.
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

-- Geometrie-Annahme:
-- Wir sind immer am unteren Rand der aktuellen Spalte und schauen nach VORNE (in den Tunnel).
-- Rückweg-Plan:
-- 1) Zur linken Kante dieser Scheibe gehen.
-- 2) 180° drehen, 'step' Blöcke nach "vorne" (also real zurück) bis Start.
-- 3) Entladen.
-- 4) 180° drehen, 'step' Blöcke wieder vor bis zur linken Kante der Scheibe.
-- 5) Von links zur gespeicherten wIdx gehen. Richtung bleibt 'goingRight'.
local function goHomeUnloadAndReturn(step, wIdx, goingRight)
  -- 1) Zur linken Kante
  local leftMoves = goingRight and (wIdx - 1) or (WIDTH - wIdx)
  for i = 1, leftMoves do moveLeft() end

  -- 2) 180° + 'step' vor bis Start
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  -- 3) Entladen in Truhe (Truhe ist jetzt VOR uns)
  for slot = 1, 16 do
    turtle.select(slot); turtle.drop()
  end
  turtle.select(1)

  -- 4) Zurück zur Scheibe
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  -- 5) Von links zur gespeicherten wIdx
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
    clearState() -- wir sind zurück, Resume nicht länger nötig
  end
end

-- ==== Start / Input ====
term.clear(); term.setCursorPos(1,1)
print("5x4 Tunnelgraber (Auto-Return)")
io.write("Wie lang soll der Tunnel sein (Bloecke)? ")
local LENGTH = tonumber(read() or "0") or 0
if LENGTH <= 0 then print("Ungueltige Laenge."); return end

-- Fuel
refuelAll()
local need = needFuelFor(LENGTH)
if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < need then
  print(("Warnung: evtl. wenig Fuel. Geschaetzt: %d, vorhanden: %d")
        :format(need, turtle.getFuelLevel()))
  print("Enter = nochmal versuchen zu refuelen, sonst direkt weiter.")
  local r = read()
  if r == "" then refuelAll() end
end

-- Falls es eine alte State-Datei gibt (z. B. Crash), bieten wir Resume an.
local resume = loadState()
if resume and resume.length == LENGTH then
  print("Gefundener Speicherstand. Resume? (j/N)")
  local ans = string.lower(read() or "")
  if ans == "j" or ans == "ja" then
    -- Zur scheibe laufen:
    -- Wir stehen am Start, schauen VORNE (in Tunnel).
    for i = 1, resume.step do ensureForward() end
    -- zur linken Kante der Scheibe (die ist direkt da, weil wir immer auf links starten)
    -- dann zur wIdx:
    for i = 1, (resume.wIdx - 1) do moveRight() end
    clearState()
    -- set locals
    -- Wir setzen stepStart = resume.step, goingRight = resume.goingRight
    -- und starten die Schleife so, dass wir mitten in der Scheibe fortfahren.
    local stepStart = resume.step
    local goingRight = resume.goingRight

    -- === Fortsetzung ab gespeicherter Stelle ===
    -- Wir befinden uns bereits in der Scheibe "stepStart" an Spalte wIdx.
    -- Wir machen die aktuelle Spalte fertig und den Rest der Scheibe und dann die restlichen Scheiben.

    -- 1) aktuelle Spalte fertig
    clearColumn(HEIGHT)
    maybeAutoReturn(stepStart, resume.wIdx, goingRight, LENGTH)

    -- 2) Restliche Spalten dieser Scheibe
    for col = resume.wIdx + 1, WIDTH do
      if goingRight then moveRight() else moveLeft() end
      clearColumn(HEIGHT)
      maybeAutoReturn(stepStart, col, goingRight, LENGTH)
    end

    -- 3) Restliche Scheiben
    local going = not goingRight
    for step = stepStart + 1, LENGTH do
      ensureForward()
      clearColumn(HEIGHT)
      maybeAutoReturn(step, 1, going, LENGTH)
      for col = 2, WIDTH do
        if going then moveRight() else moveLeft() end
        clearColumn(HEIGHT)
        maybeAutoReturn(step, col, going, LENGTH)
      end
      going = not going
    end

    -- Am Ende zur linken Kante, heim, entladen
    if not going then
      -- stehen rechts -> nach links rueber
      for i = 1, WIDTH - 1 do moveLeft() end
    end
    turtle.turnLeft(); turtle.turnLeft()
    for i = 1, LENGTH do ensureForward() end
    dumpToChestBehind()
    print("Fertig mit Resume. :)")
    return
  else
    clearState()
  end
end

-- ==== Frischer Run ====
local goingRight = true

for step = 1, LENGTH do
  -- in diese Scheibe vorruecken
  ensureForward()
  -- Spalte 1
  clearColumn(HEIGHT)
  maybeAutoReturn(step, 1, goingRight, LENGTH)

  -- Restliche Spalten
  for wIdx = 2, WIDTH do
    if goingRight then moveRight() else moveLeft() end
    clearColumn(HEIGHT)
    maybeAutoReturn(step, wIdx, goingRight, LENGTH)
  end

  goingRight = not goingRight
end

-- Am Ende ggf. von rechts nach links rueber
if goingRight == false then
  -- letzte Scheibe endete rechts -> nach links
  for i = 1, WIDTH - 1 do moveLeft() end
end

-- Heim + Entladen
turtle.turnLeft(); turtle.turnLeft()
for i = 1, LENGTH do ensureForward() end
dumpToChestBehind()
print("Fertig! 5x4-Tunnel gegraben und entladen.")
