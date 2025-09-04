-- turtleMonitorGUI.lua
-- Advanced-Computer GUI mit Tabs: Fuel, Slots, Steps.
-- Hört Telemetrie auf "turtleStatus" und Chat auf "turtleChat".
local MODEM_SIDE = "left"  -- bei dir links

rednet.open(MODEM_SIDE)
local mon = peripheral.find("monitor")
local out = mon or term
if mon then mon.setTextScale(0.5) end

local w, h = out.getSize()

local state = {
  fuel = 0, needHome = 0,
  step = 0, length = 0,
  col = 1, width = 5,
  dir = "right",
  slotsFree = 16,
  lastChat = {},
  lastTs = 0,
}
local TAB = 1 -- 1=Fuel, 2=Slots, 3=Steps

local function clr(bg, fg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; if out.setTextColor then out.setTextColor(fg) end end
local function fillRect(x1,y1,x2,y2,bg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; for y=y1,y2 do out.setCursorPos(x1,y); out.write(string.rep(" ", x2-x1+1)) end end
local function writeAt(x,y,text,color) if color and out.setTextColor then out.setTextColor(color) end; out.setCursorPos(x,y); out.write(text) end
local function bar(x,y,wid,ratio,okColor,warnColor)
  ratio = math.max(0, math.min(1, ratio or 0))
  local fill = math.floor(wid * ratio + 0.5)
  local c = (ratio < 0.2) and colors.red or ((ratio < 0.45) and warnColor or okColor)
  clr(colors.gray, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", wid))
  clr(c, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", fill))
end

local function header()
  fillRect(1,1,w,1,colors.gray); clr(colors.gray, colors.black)
  local ttl = "🐢 Turtle Dashboard"
  out.setCursorPos(math.max(1, math.floor((w-#ttl)/2)), 1); out.write(ttl)
end
local function tabs()
  local names = {"Fuel","Slots","Steps"}
  local x = 2
  for i=1,#names do
    local label = " "..i..":"..names[i].." "
    local col = (i==TAB) and colors.cyan or colors.lightGray
    clr(col, colors.black); out.setCursorPos(x,3); out.write(label)
    x = x + #label + 1
  end
end
local function footer()
  local y = h-2
  fillRect(1,y,w,h,colors.black); clr(colors.black, colors.lightGray)
  out.setCursorPos(1,y); out.write("Protokoll: turtleStatus / turtleChat  |  Keys: [1][2][3] Tabs, [<-][->] Wechsel, [Q]uit")
  if #state.lastChat > 0 then
    local msg = state.lastChat[#state.lastChat]
    writeAt(1,h, (type(msg)=="string" and msg or textutils.serialize(msg)):sub(1,w), colors.white)
  end
end

local function viewFuel()
  fillRect(1,4,w,h-3,colors.black)
  writeAt(2,5,  "Fuel:", colors.white)
  local est = (state.length or 0)*35+150
  local lvl = (state.fuel=="unlimited") and est or tonumber(state.fuel) or 0
  local ratio = est>0 and (lvl/est) or 0
  bar(9,5,w-10, ratio, colors.green, colors.yellow)
  writeAt(2,7,  ("Fuel Level: %s"):format(tostring(state.fuel)), colors.white)
  writeAt(2,8,  ("Heimweg (min): %d"):format(state.needHome or 0), colors.white)
  local warn = (state.fuel ~= "unlimited") and (tonumber(state.fuel) or 0) < (state.needHome or 0)
  writeAt(2,10, warn and "WARNUNG: Fuel knapp für Heimweg!" or "Status: ausreichend für Heimweg ✅",
    warn and colors.red or colors.green)
end

local function viewSlots()
  fillRect(1,4,w,h-3,colors.black)
  local free = state.slotsFree or 16
  local used = 16 - free
  writeAt(2,5,  "Inventar:", colors.white)
  bar(12,5,w-13, used/16, colors.lime, colors.orange)
  writeAt(2,7, ("Frei: %d  |  Belegt: %d / 16"):format(free, used), colors.white)
  if free <= 0 then
    writeAt(2,9, "INVENTAR VOLL! Heimkehr aktiv.", colors.red)
  elseif free <= 1 then
    writeAt(2,9, "Achtung: Fast voll! Auto-Return bald.", colors.yellow)
  else
    writeAt(2,9, "Alles gut. Mining weiter stabil.", colors.green)
  end
end

local function viewSteps()
  fillRect(1,4,w,h-3,colors.black)
  local step = state.step or 0
  local len  = state.length or 0
  local col  = state.col or 1
  local wid  = state.width or 5
  writeAt(2,5, ("Tunnel Fortschritt:"), colors.white)
  local ratio = (len>0) and (step/len) or 0
  bar(22,5,w-23, ratio, colors.blue, colors.yellow)
  writeAt(2,7, ("Step: %d / %d"):format(step, len), colors.white)
  writeAt(2,8, ("Breite-Spalte: %d / %d  (Richtung: %s)"):format(col, wid, state.dir or "?"), colors.white)
end

local function draw()
  header(); tabs()
  if     TAB==1 then viewFuel()
  elseif TAB==2 then viewSlots()
  else               viewSteps()
  end
  footer()
end

out.setBackgroundColor(colors.black); out.clear(); out.setCursorPos(1,1)
draw()
local timer = os.startTimer(0.3)

while true do
  local ev = { os.pullEvent() }
  if ev[1] == "rednet_message" then
    local sender, msg, proto = ev[2], ev[3], ev[4]
    if proto == "turtleStatus" then
      local data = msg
      if type(msg) == "string" then
        data = textutils.unserialize(msg) or (textutils.unserializeJSON and textutils.unserializeJSON(msg)) or nil
      end
      if type(data) == "table" and data.type=="status" then
        state.fuel     = data.fuel     or state.fuel
        state.needHome = data.needHome or state.needHome
        state.step     = data.step     or state.step
        state.length   = data.length   or state.length
        state.col      = data.col      or state.col
        state.width    = data.width    or state.width
        state.dir      = data.dir      or state.dir
        state.lastTs   = data.ts       or os.clock()
        draw()
      end
    elseif proto == "turtleChat" then
      state.lastChat[#state.lastChat+1] = msg
      if #state.lastChat > 5 then table.remove(state.lastChat,1) end
      draw()
    end

  elseif ev[1] == "key" then
    local key = ev[2]
    if key == keys.one then TAB = 1; draw()
    elseif key == keys.two then TAB = 2; draw()
    elseif key == keys.three then TAB = 3; draw()
    elseif key == keys.left then TAB = ((TAB+1)%3)+1; draw()
    elseif key == keys.right then TAB = (TAB%3)+1; draw()
    elseif key == keys.q then break end

  elseif ev[1] == "monitor_touch" then
    local mx, my = ev[3], ev[4]
    if my == 3 then
      if mx <= math.floor(w/3) then TAB=1 elseif mx <= math.floor(2*w/3) then TAB=2 else TAB=3 end
      draw()
    end

  elseif ev[1] == "timer" and ev[2] == timer then
    draw()
    timer = os.startTimer(0.5)
  end
end
