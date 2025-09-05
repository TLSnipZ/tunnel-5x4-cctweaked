-- turtleMonitorMulti.lua (v3 responsive: rich view + compact fallback)
-- Ender-Modem, Multi-Turtle Tabs, detaillierte Anzeigen (Fuel/Slots/Progress),
-- Chat-Box je Turtle, große Klickflächen, Auto-Scale fuer Mini- und Maxi-Monitore.

-- ============== Monitor Auto-Scale ==============
local function attachMonitorAuto(minCols, minRows, fallbackScale)
  local m = peripheral.find("monitor")
  if not m then return nil end
  local picked=nil
  for s=5,0.5,-0.5 do
    m.setTextScale(s)
    local w,h=m.getSize()
    if w>=minCols and h>=minRows then picked=s; break end
  end
  if not picked then m.setTextScale(fallbackScale or 0.5) end
  return m
end

-- Für rich view peilen wir ~50x14 an, fallen aber automatisch auf compact zurück
local mon = attachMonitorAuto(24, 8, 0.5)
local out = mon or term
local W,H = out.getSize()

-- ============== Ender-Modems öffnen ==============
for _,side in ipairs(rs.getSides()) do
  if peripheral.getType(side)=="modem" then pcall(rednet.open, side) end
end

-- ============== State ==============
local turtles = {}  -- name -> { fuel, needHome, step, length, col, width, dir, slotsFree, chat={}, lastSeen }
local order = {}
local activeIdx = 1

local function ensureInOrder(name)
  for i=1,#order do if order[i]==name then return end end
  table.insert(order, name)
end

-- ============== Utils ==============
local function clr(bg,fg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; if out.setTextColor then out.setTextColor(fg) end end
local function fill(x1,y1,x2,y2,bg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; for yy=y1,y2 do out.setCursorPos(x1,yy); out.write(string.rep(" ", x2-x1+1)) end end
local function writeAt(x,y,t,c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(x,y); out.write(t) end
local function center(y, txt, c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(math.max(1, math.floor((W-#txt)/2)), y); out.write(txt) end
local function bar(x,y,wid,ratio,okColor,warnColor)
  ratio=math.max(0,math.min(1,ratio or 0))
  local fillw=math.floor(wid*ratio+0.5)
  clr(colors.gray, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", wid))
  local c=(ratio<0.2) and colors.red or ((ratio<0.45) and warnColor or okColor)
  clr(c, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", fillw))
end

-- Parse Turtle-Name aus Chat-String wie "🐢 [alpha] ... "
local function parseNameFromChat(s)
  if type(s)~="string" then return nil end
  local name = s:match("%[(.-)%]")  -- zwischen [ ]
  if name and #name>0 then return name end
  return nil
end

-- ============== RICH VIEW (große Monitore) ==============
local function headerRich()
  fill(1,1,W,1,colors.gray); clr(colors.gray, colors.black)
  center(1, "🐢 Turtle Monitor (Ender) – Tabs: 1..9 / ← →   |   Q=Quit  F5=Refresh", colors.black)
end

local function tabsRich()
  fill(1,3,W,3,colors.black)
  local x=2
  for i,name in ipairs(order) do
    local sel = (i==activeIdx)
    local label = (" %d:%s "):format(i, name)
    clr(sel and colors.cyan or colors.lightGray, colors.black)
    out.setCursorPos(x,3); out.write(label)
    x = x + #label + 1
    if x > W-6 then break end
  end
end

local function footerRich()
  local y=H-2; fill(1,y,W,H,colors.black)
  local btns = {
    {label="[P]ause", x=2,  col=colors.lightBlue, key="pause"},
    {label="[R]esume",x=12, col=colors.lime,      key="resume"},
    {label="[S]top",  x=24, col=colors.red,       key="stop"},
    {label="[V]erbose",x=34,col=colors.yellow,    key="verbose"},
  }
  for _,b in ipairs(btns) do writeAt(b.x, y, b.label, b.col) end
end

local function viewTurtleRich(name)
  fill(1,4,W,H-3,colors.black)
  local t = turtles[name]
  if not t then
    writeAt(2,6,"Warte auf Turtle: "..(name or "?"), colors.yellow)
    return
  end

  -- Kopfzeile
  writeAt(2,4, ("Turtle: %s   |   Last: %s"):format(name, os.date and os.date("%H:%M:%S") or tostring(os.clock())), colors.white)

  -- Fuel
  writeAt(2,6, "Fuel:", colors.white)
  local est=(t.length or 0)*35 + 150
  local lvl=(t.fuel=="unlimited") and est or tonumber(t.fuel) or 0
  bar(10,6, W-12, (est>0 and lvl/est or 0), colors.green, colors.yellow)
  writeAt(2,7, ("Level: %s   Heimweg: %d   Empfehlung: ~%d")
    :format(tostring(t.fuel), t.needHome or 0, est), colors.lightGray)

  -- Slots
  local free=t.slotsFree or 16; local used=16-free
  writeAt(2,9, "Slots:", colors.white)
  bar(10,9, W-12, used/16, colors.lime, colors.orange)
  writeAt(2,10, ("Frei: %d   Belegt: %d/16"):format(free, used), colors.lightGray)

  -- Progress
  writeAt(2,12, "Progress:", colors.white)
  bar(12,12, W-14, ((t.step or 0)/math.max(1,(t.length or 1))), colors.blue, colors.yellow)
  writeAt(2,13, ("Step: %d / %d   Spalte: %d/%d   Richtung: %s")
    :format(t.step or 0, t.length or 0, t.col or 1, t.width or 5, t.dir or "?"), colors.lightGray)

  -- Chat-Box (3–5 Zeilen je nach Höhe)
  local chatPad = math.min( math.max(3, H-15), 6 )
  local yStart = H - 2 - chatPad
  fill(1, yStart-1, W, yStart-1, colors.gray); clr(colors.gray, colors.black)
  writeAt(2, yStart-1, " Chat ", colors.black)
  clr(colors.black, colors.lightGray)
  for i=chatPad-1,0,-1 do
    local msg = t.chat and t.chat[#t.chat - i] or ""
    if msg then
      local txt = tostring(msg):gsub("\n"," ")
      if #txt > W-2 then txt = txt:sub(1, W-5).."..." end
      writeAt(2, yStart + (chatPad-1 - i), txt, colors.lightGray)
    end
  end
end

-- ============== COMPACT VIEW (Mini-Monitore) ==============
local function headerCompact()
  fill(1,1,W,1,colors.gray); clr(colors.gray, colors.black)
  center(1, "Turtles", colors.black)
end
local function tabsCompact()
  fill(1,2,W,2,colors.black)
  if #order==0 then return end
  local segW = math.max(3, math.floor(W / math.min(#order, 6)))
  local x=1
  for i=1,math.min(#order, 6) do
    local sel = (i==activeIdx)
    local label = tostring(i)
    clr(sel and colors.cyan or colors.lightGray, colors.black)
    out.setCursorPos(x + math.floor((segW-#label)/2), 2); out.write(label)
    x = x + segW
  end
end
local function footerCompact()
  local y = H-1
  if y < 4 then return end
  fill(1,y,W,y,colors.black)
  local slot = math.max(1, math.floor(W/4))
  writeAt(2,         y, "P", colors.lightBlue)
  writeAt(2+slot,    y, "R", colors.lime)
  writeAt(2+2*slot,  y, "S", colors.red)
  writeAt(2+3*slot,  y, "V", colors.yellow)
end
local function viewTurtleCompact(name)
  fill(1,3,W,H-2,colors.black)
  local t = turtles[name]
  if not t then writeAt(2,4,"Warte auf: "..(name or "?"), colors.yellow); return end

  writeAt(2,3, (name or "?"):sub(1, W-4), colors.white)
  if H>=5 then
    local est=(t.length or 0)*35 + 150
    local lvl=(t.fuel=="unlimited") and est or tonumber(t.fuel) or 0
    writeAt(2,4,"F:", colors.white)
    bar(5,4, W-6, (est>0 and lvl/est or 0), colors.green, colors.yellow)
  end
  if H>=6 then
    local free=t.slotsFree or 16; local used=16-free
    writeAt(2,5,"S:", colors.white)
    bar(5,5, W-6, used/16, colors.lime, colors.orange)
  end
  if H>=7 then
    writeAt(2,6,"P:", colors.white)
    bar(5,6, W-6, ((t.step or 0)/math.max(1,(t.length or 1))), colors.blue, colors.yellow)
  end

  -- Chat (1–2 Zeilen)
  local chatLines = math.max(1, (H>=9 and 2) or 1)
  local yStart = H - chatLines
  for i=0,chatLines-1 do
    local msg = t.chat and t.chat[#t.chat - (chatLines-1) + i] or ""
    if msg then
      local txt = tostring(msg):gsub("\n"," ")
      if #txt > W-2 then txt = txt:sub(1, W-5).."..." end
      writeAt(2, yStart + i, txt, colors.lightGray)
    end
  end
end

-- ============== Dispatcher (responsive) ==============
local function draw()
  local rich = (W>=50 and H>=14)
  if rich then
    headerRich(); tabsRich()
    local name = order[activeIdx]
    if name then viewTurtleRich(name) else
      fill(1,4,W,H-3,colors.black); writeAt(2, math.max(4, math.floor(H/2)), "Warte auf Turtles...", colors.yellow)
    end
    footerRich()
  else
    headerCompact(); tabsCompact()
    local name = order[activeIdx]
    if name then viewTurtleCompact(name) else
      fill(1,3,W,H-2,colors.black); writeAt(2, math.max(3, math.floor(H/2)), "Warte auf Turtles...", colors.yellow)
    end
    footerCompact()
  end
end

-- ============== Control ==============
local function sendCmd(name, cmd)
  if not name then return end
  local id = rednet.lookup("turtleCtl", name)
  if id then rednet.send(id, cmd, "turtleCtl")
  else rednet.broadcast({target=name, cmd=cmd}, "turtleCtl") end
end

-- ============== Event Loop ==============
out.setBackgroundColor(colors.black); out.clear()
draw()
local timer = os.startTimer(0.35)

while true do
  local ev = { os.pullEvent() }

  if ev[1]=="rednet_message" then
    local _, msg, proto = ev[2], ev[3], ev[4]

    if proto=="turtleStatus" then
      local data = msg
      if type(msg)=="string" then data=textutils.unserialize(msg) or (textutils.unserializeJSON and textutils.unserializeJSON(msg)) end
      if type(data)=="table" and data.type=="status" and data.name then
        local t = turtles[data.name] or {chat={}}
        for k,v in pairs(data) do if k~="type" then t[k]=v end end
        t.lastSeen = os.time()
        turtles[data.name] = t
        ensureInOrder(data.name)
        draw()
      end

    elseif proto=="turtleChat" then
      local s = tostring(msg or "")
      local who = parseNameFromChat(s)
      if who then
        turtles[who] = turtles[who] or {chat={}}
        local c = turtles[who].chat or {}
        c[#c+1] = s
        if #c > 20 then table.remove(c,1) end
        turtles[who].chat = c
        draw()
      else
        local name = order[activeIdx]
        if name then
          turtles[name] = turtles[name] or {chat={}}
          local c = turtles[name].chat or {}
          c[#c+1] = s
          if #c > 20 then table.remove(c,1) end
          turtles[name].chat = c
          draw()
        end
      end
    end

  elseif ev[1]=="key" then
    local k = ev[2]
    if k==keys.left then if #order>0 then activeIdx=((activeIdx-2)%#order)+1; draw() end
    elseif k==keys.right then if #order>0 then activeIdx=(activeIdx%#order)+1; draw() end
    elseif k==keys.one or k==2 or k==3 or k==4 or k==5 or k==6 or k==7 or k==8 or k==9 then
      local map={ [keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.four]=4,[keys.five]=5,[keys.six]=6,[keys.seven]=7,[keys.eight]=8,[keys.nine]=9 }
      local idx=map[k]; if idx and order[idx] then activeIdx=idx; draw() end
    elseif k==keys.q then break
    elseif k==keys.p then if order[activeIdx] then sendCmd(order[activeIdx],"pause") end
    elseif k==keys.r then if order[activeIdx] then sendCmd(order[activeIdx],"resume") end
    elseif k==keys.s then if order[activeIdx] then sendCmd(order[activeIdx],"stop") end
    elseif k==keys.v then if order[activeIdx] then sendCmd(order[activeIdx],"verbose") end
    elseif k==keys.f5 then draw()
    end

  elseif ev[1]=="monitor_touch" then
    local mx,my = ev[3], ev[4]
    local rich = (W>=50 and H>=14)
    -- Tabs
    if (rich and my==3) or (not rich and my==2) then
      if #order>0 then
        if rich then
          -- Tabs stehen nebeneinander, einfache Annäherung: suche per Lauf
          local x=2
          for i,name in ipairs(order) do
            local label=(" %d:%s "):format(i, name)
            local x2 = x + #label - 1
            if mx>=x and mx<=x2 then activeIdx=i; break end
            x = x + #label + 1
            if x>W-6 then break end
          end
        else
          local segW = math.max(3, math.floor(W / math.min(#order, 6)))
          local idx = math.floor((mx-1)/segW) + 1
          if idx>=1 and idx<=math.min(#order,6) then activeIdx = idx end
        end
        draw()
      end
    -- Buttons
    elseif (rich and my==H-2) or (not rich and my==H-1) then
      local name = order[activeIdx]
      if name then
        if rich then
          -- harte Boxen
          if mx>=2 and mx<=9   then sendCmd(name,"pause")
          elseif mx>=12 and mx<=20 then sendCmd(name,"resume")
          elseif mx>=24 and mx<=29 then sendCmd(name,"stop")
          elseif mx>=34 and mx<=43 then sendCmd(name,"verbose") end
        else
          local slot = math.max(1, math.floor(W/4))
          local idx = math.floor((mx-1)/slot) + 1
          if idx==1 then sendCmd(name,"pause")
          elseif idx==2 then sendCmd(name,"resume")
          elseif idx==3 then sendCmd(name,"stop")
          elseif idx==4 then sendCmd(name,"verbose") end
        end
        draw()
      end
    end

  elseif ev[1]=="timer" and ev[2]==timer then
    draw(); timer=os.startTimer(0.35)
  end
end
