-- turtleMonitorMulti.lua
-- Multi-Turtle Monitor GUI (Ender-Modem): Tabs je Turtle-Name, Live Fuel/Slots/Steps,
-- Buttons: Pause/Resume/Stop/Verbose fuer die ausgewaehlte Turtle.
-- Auto-Scale fuer Monitore; faellt auf Terminal zurueck.

-- ====== Auto-Scale Monitor ======
local function attachMonitorAuto(minCols, minRows, fallbackScale)
  local m = peripheral.find("monitor")
  if not m then return nil end
  local picked=nil
  for s=5,0.5,-0.5 do
    m.setTextScale(s)
    local w,h = m.getSize()
    if w>=minCols and h>=minRows then picked=s; break end
  end
  if not picked then m.setTextScale(fallbackScale or 0.5) end
  return m
end
local mon = attachMonitorAuto(64, 18, 0.5)
local out = mon or term
local W,H = out.getSize()

-- ====== Ender-Modem: alle Modems oeffnen ======
for _,side in ipairs(rs.getSides()) do
  if peripheral.getType(side)=="modem" then pcall(rednet.open, side) end
end

-- ====== State ======
local turtles = {}   -- name -> {fuel, needHome, step, length, col, width, dir, slotsFree, lastSeen}
local order = {}     -- Tab-Reihenfolge
local activeIdx = 1  -- Index in 'order'

local function ensureInOrder(name)
  for i=1,#order do if order[i]==name then return end end
  table.insert(order, name)
end

-- ====== Draw Utils ======
local function clr(bg,fg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; if out.setTextColor then out.setTextColor(fg) end end
local function fill(x1,y1,x2,y2,bg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; for yy=y1,y2 do out.setCursorPos(x1,yy); out.write(string.rep(" ", x2-x1+1)) end end
local function writeAt(x,y,t,c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(x,y); out.write(t) end
local function bar(x,y,wid,ratio,okColor,warnColor) ratio=math.max(0,math.min(1,ratio or 0)); local fillw=math.floor(wid*ratio+0.5); clr(colors.gray, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ",wid)); local c=(ratio<0.2) and colors.red or ((ratio<0.45) and warnColor or okColor); clr(c, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", fillw)) end

local buttons = {
  {label="[P]ause",   key="pause",   x1=2,  x2=9,  color=colors.lightBlue},
  {label="[R]esume",  key="resume",  x1=11, x2=18, color=colors.lime},
  {label="[S]top",    key="stop",    x1=20, x2=25, color=colors.red},
  {label="[V]erbose", key="verbose", x1=27, x2=35, color=colors.yellow},
}

-- ====== UI ======
local function header()
  fill(1,1,W,1,colors.gray); clr(colors.gray, colors.black)
  local ttl="🐢 Turtle Monitor (Ender) - Tabs: 1..9 / ← →"
  out.setCursorPos(math.max(1, math.floor((W-#ttl)/2)),1); out.write(ttl)
end

local function tabs()
  fill(1,3,W,3,colors.black)
  local x=2
  for i,name in ipairs(order) do
    local sel = (i==activeIdx)
    local label = " "..i..":"..name.." "
    clr(sel and colors.cyan or colors.lightGray, colors.black)
    out.setCursorPos(x,3); out.write(label)
    x = x + #label + 1
  end
end

local function footer()
  local y=H-2; fill(1,y,W,H,colors.black)
  for _,b in ipairs(buttons) do writeAt(b.x1, y, b.label, b.color) end
  writeAt(W-20, H, "Q=Quit | F5=Refresh", colors.lightGray)
end

local function viewTurtle(name)
  fill(1,4,W,H-3,colors.black)
  local t = turtles[name]
  if not t then writeAt(2,5,"Keine Daten fuer: "..name, colors.red); return end

  writeAt(2,5,("Turtle: %s"):format(name), colors.white)
  writeAt(2,6,("Zuletzt: %s"):format(os.date and os.date("%H:%M:%S") or tostring(os.clock())), colors.lightGray)

  writeAt(2,8,"Fuel:",colors.white)
  local est=(t.length or 0)*35 + 150
  local lvl=(t.fuel=="unlimited") and est or tonumber(t.fuel) or 0
  bar(9,8,W-10, (est>0 and lvl/est or 0), colors.green, colors.yellow)
  writeAt(2,9,("Fuel Level: %s | Heim: %d"):format(tostring(t.fuel), t.needHome or 0), colors.white)

  local free=t.slotsFree or 16; local used=16-free
  writeAt(2,11,"Slots:",colors.white)
  bar(9,11,W-10, used/16, colors.lime, colors.orange)
  writeAt(2,12,("Frei: %d  |  Belegt: %d/16"):format(free, used), colors.white)

  writeAt(2,14,"Fortschritt:",colors.white)
  bar(16,14,W-17, ((t.step or 0)/math.max(1,(t.length or 1))), colors.blue, colors.yellow)
  writeAt(2,15,("Step: %d / %d"):format(t.step or 0, t.length or 0), colors.white)
  writeAt(2,16,("Spalte: %d/%d  Richtung: %s"):format(t.col or 1, t.width or 5, t.dir or "?"), colors.white)
end

local function draw()
  header(); tabs()
  local name = order[activeIdx]
  if name then viewTurtle(name) else
    fill(1,4,W,H-3,colors.black); writeAt(2,6,"Warte auf Turtle-Status...", colors.yellow)
  end
  footer()
end

-- ====== Control (gezielt an Turtle) ======
local function sendCmd(name, cmd)
  if not name then return end
  -- gezielt per lookup zum Host
  local id = rednet.lookup("turtleCtl", name)
  if id then
    rednet.send(id, cmd, "turtleCtl") -- direkt an die Turtle
  else
    -- Fallback broadcast mit target
    rednet.broadcast({target=name, cmd=cmd}, "turtleCtl")
  end
end

-- ====== Main Loop ======
out.setBackgroundColor(colors.black); out.clear(); out.setCursorPos(1,1)
draw()
local timer=os.startTimer(0.5)

while true do
  local ev={ os.pullEvent() }

  if ev[1]=="rednet_message" then
    local _, msg, proto = ev[2], ev[3], ev[4]
    if proto=="turtleStatus" then
      local data=msg
      if type(msg)=="string" then data=textutils.unserialize(msg) or (textutils.unserializeJSON and textutils.unserializeJSON(msg)) end
      if type(data)=="table" and data.type=="status" and data.name then
        turtles[data.name] = turtles[data.name] or {}
        for k,v in pairs(data) do if k~="type" then turtles[data.name][k]=v end end
        turtles[data.name].lastSeen = os.time()
        ensureInOrder(data.name)
        draw()
      end
    elseif proto=="turtleChat" then
      -- optional: koennte man als Ticker anzeigen
    end

  elseif ev[1]=="key" then
    local k = ev[2]
    if k==keys.left then if #order>0 then activeIdx = ((activeIdx-2) % #order) + 1; draw() end
    elseif k==keys.right then if #order>0 then activeIdx = (activeIdx % #order) + 1; draw() end
    elseif k==keys.one or k==2 or k==3 or k==4 or k==5 or k==6 or k==7 or k==8 or k==9 then
      local map={ [keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.four]=4,[keys.five]=5,[keys.six]=6,[keys.seven]=7,[keys.eight]=8,[keys.nine]=9 }
      local idx = map[k]; if idx and order[idx] then activeIdx=idx; draw() end
    elseif k==keys.q then break
    elseif k==keys.p then if order[activeIdx] then sendCmd(order[activeIdx],"pause") end
    elseif k==keys.r then if order[activeIdx] then sendCmd(order[activeIdx],"resume") end
    elseif k==keys.s then if order[activeIdx] then sendCmd(order[activeIdx],"stop") end
    elseif k==keys.v then if order[activeIdx] then sendCmd(order[activeIdx],"verbose") end
    elseif k==keys.f5 then draw()
    end

  elseif ev[1]=="monitor_touch" then
    local mx,my=ev[3],ev[4]
    -- Tabs (Zeile 3)
    if my==3 then
      -- grob in N Segmente teilen
      if #order>0 then
        local seg = math.max(1, math.min(#order, math.floor((mx-1) / math.max(1, math.floor(W/#order))) + 1))
        activeIdx = seg; draw()
      end
    -- Buttons (vorletzte Zeile)
    elseif my==H-2 then
      local name = order[activeIdx]
      if not name then else
        if mx>=2 and mx<=9   then sendCmd(name,"pause")
        elseif mx>=11 and mx<=18 then sendCmd(name,"resume")
        elseif mx>=20 and mx<=25 then sendCmd(name,"stop")
        elseif mx>=27 and mx<=35 then sendCmd(name,"verbose")
        end
      end
      draw()
    end

  elseif ev[1]=="timer" and ev[2]==timer then
    draw(); timer=os.startTimer(0.5)
  end
end
