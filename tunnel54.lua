-- tunnel54.lua
-- 5x4 Tunnel mit Auto-Return, Auto-Refuel, Auto-Torch-Placement, Resume,
-- Fun-Sprüchen und Fackel-Schutz (Torchs werden nicht wieder abgebaut).

local WIDTH       = 5
local HEIGHT      = 4
local STATE_FILE  = "tunnel54.state"
local VERBOSE     = true
local TORCH_INTERVAL = 6
local TORCH_NAME = "minecraft:torch"

-- Fuel-Konstanten
local FUEL_COAL       = 80
local FUEL_COAL_BLOCK = 720
local FUEL_LAVA       = 1000

-- Fun Sprüche (große Liste)
local randomQuotes = {
  "Brudi, hier unten isses dunkler als in meiner Zukunft 😅",
  "Stein um Stein... ich fühl mich wie Bob der Baumeister 🛠️",
  "Warum grab ich eigentlich und nicht du? 🤔",
  "Wenn hier Lava kommt, geb ich dir die Schuld 🔥",
  "Slots platzen gleich wie mein Terminkalender 📅",
  "Bro, ich schwitz mehr als du aufm Festival 😂",
  "Mining-Turtle: 1, Kies: 0 💪",
  "Tunnel-Business läuft stabil 📈",
  "Fühl mich wie ne S-Bahn: hin, zurück, hin, zurück 🚆",
  "Hab Bock auf 'nen Döner nach Schichtende 🌯",
  "Wenn Kies von oben droppt = mein Herz droppt auch 💔",
  "Hab mehr Blöcke gesehen als du Insta-Reels 📱",
  "Wenn Sprit alle → push mich nach Hause 😭",
  "Arbeiten ohne Musik? Stell mir wenigstens Spotify rein 🎶",
  "Hab Albträume von Gravel... ⛏️",
  "Loot-Slots voll = wie 'ne Tasche nach dem Einkaufen 🛍️",
  "Ohne Fackeln isses hier düster wie Montagsmorgens ☠️",
  "Tunnel done faster than deine Hausaufgaben ✍️",
  "Kohle tanken ist mein Energy-Drink 🔋",
  "Bin basically dein Praktikant, nur kostenlos 🤓",
  "Tunnel gerade wie 'ne Tuning-Achse (hoffentlich) 🚗",
  "Muss mich kurz resetten, Akku fast low 🔄",
  "Ich schwör, ich bau dir Minecraft-Autobahnen 🛣️",
  "Lava spotted, Herz in Hose gerutscht 🩳🔥",
  "Slots frei? Selten, Bruder... selten.",
  "Tunnel-Job = Leg Day für Turtles 🐢",
  "Bisschen mehr Sprit und ich würd bis Australien graben 🌏",
  "Ich setz dir mehr Fackeln als du Likes auf Insta hast 😂",
  "Bagger, aber in cute 🐢💚",
  "Mission Mining Impossible 🎬",
}

-- === Output Helpers ===
local function randomChat()
  if not VERBOSE then return end
  if math.random(1, 10) == 1 then
    local msg = randomQuotes[math.random(1, #randomQuotes)]
    print("🐢 "..msg)
  end
end

local function say(fmt, ...)
  print("🐢 "..string.format(fmt, ...))
end

-- === Utils ===
local function refuelAll()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then turtle.refuel(64) end
  end
  turtle.select(1)
end

-- ensureForward: jetzt mit Torch-Schutz
local function ensureForward()
  while turtle.detect() do
    local success, data = turtle.inspect()
    if success and data.name == TORCH_NAME then
      if turtle.forward() then return end
    else
      turtle.dig()
      sleep(0.05)
    end
  end
  while not turtle.forward() do
    turtle.attack()
    turtle.dig()
    sleep(0.05)
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
local function moveLeft()  turtle.turnLeft(); ensureForward(); turtle.turnRight() end

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

-- === State ===
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

-- === Fuel & Return ===
local function distanceToLeft(wIdx, goingRight)
  if goingRight then return (wIdx - 1) else return (WIDTH - wIdx) end
end

local function refuelFromChestFront()
  for i = 1, 8 do turtle.suck(64) end
  refuelAll()
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
  local leftMoves = distanceToLeft(wIdx, goingRight)
  for i = 1, leftMoves do moveLeft() end

  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end

  say("Back @ Home – loot droppen 🚛")
  for slot = 1, 16 do turtle.select(slot); turtle.drop() end
  turtle.select(1)

  say("Check Sprit & Fackeln in der Kiste 🛠️🔥")
  refuelFromChestFront()
  takeTorchesFromChest()

  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, step do ensureForward() end
  for i = 1, (wIdx - 1) do moveRight() end
  say("Jo, zurück am Arbeitsplatz ⛏️")
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
        say("Fackel gesetzt 🔦 (Step %d)", step)
        return
      end
    end
  end
end

local function status(step, wIdx, goingRight, length)
  if not VERBOSE then return end
  local reserve = 5
  local needHome = distanceToLeft(wIdx, goingRight) + step + reserve
  local lvl = turtle.getFuelLevel()
  say("[Step %d/%d | Col %d/%d] Fuel: %s | Heim min: %d | Slots frei: %d",
    step, length, wIdx, WIDTH, tostring(lvl), needHome, slotsFree())
  randomChat()
end

local function maybeAutoReturn(step, wIdx, goingRight, length)
  if invFull() then
    say("Inventar voll, ab nach Hause 👜➡️")
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
    say("Fuel low – retreat! 🛢️")
    saveState(step, wIdx, goingRight, length)
    goHomeUnloadAndReturn(step, wIdx, goingRight)
    clearState()
  end
end

-- === Main ===
term.clear(); term.setCursorPos(1,1)
say("Tunnel-Mode ON 🐢💨 (mit Fackel-Service & random Chat)")

io.write("Wie lang soll der Tunnel sein (Bloecke)? ")
local LENGTH = tonumber(read() or "0") or 0
if LENGTH <= 0 then say("Ey, gib mal ne gescheite Zahl 🙃"); return end

local est = estimateTotalFuel(LENGTH)
say("Für %d Blöcke brauch ich grob %d Fuel.", LENGTH, est)
say("~%d Kohle | %d Kohleblöcke | %d Lavaeimer",
  math.ceil(est / FUEL_COAL), math.ceil(est / FUEL_COAL_BLOCK), math.ceil(est / FUEL_LAVA))

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

if goingRight == false then for i = 1, WIDTH - 1 do moveLeft() end end
turtle.turnLeft(); turtle.turnLeft()
for i = 1, LENGTH do ensureForward() end
dumpToChestBehind()
say("Tunnel abgeschlossen! Loot & Licht ✅")
