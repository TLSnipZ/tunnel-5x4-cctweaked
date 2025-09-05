-- turtleMonitorMulti.lua (Compact v2)
-- Optimiert fuer sehr kleine Monitore (z.B. 5x3 Bloecke).
-- Features: Multi-Turtle Tabs, Live Fuel/Slots/Steps, Buttons (Pause/Resume/Stop/Verbose),
-- breitere Klickzonen, Chat-Box je Turtle unten im Tab, Ender-Modem Support.

-- ====== Auto-Scale Monitor (kompakt) ======
local function attachMonitorAuto(minCols, minRows, fallbackScale)
  local m = peripheral.find("monitor")
  if not m then return nil end
  local picked=nil
  for s=5,0.5,-0.5 do
    m.setTextScale(s)
    local w,h=m.getSize()
    if w>=minCols and h>=minRows then picked=s; break end
  end
  if not picked then m.setTextScale(fallbackScale or 1.0) end
  return m
end

-- Fuer sehr kleine Displays reichen ~24x8
local mon = attachMonitorAuto(24, 8, 1.0)
local out = mon or term
local W,H = out.getSize()

-- ====== Ender-Modems oeffnen ======
for _,side in ipairs(rs.getSides()) do
  if peripheral.getType(side)=="modem" then pcall(rednet.open, side) end
end

-- ====== State ======
local turtles = {}  -- name -> { fuel, needHome, step, length, col, width, dir, slotsFree, chat={}, lastSeen }
local order = {}    -- Tab-Reihenfolge
local activeIdx = 1

local function ensureInOrder(name)
  for i=1,#order do if order[i]==name then return end end
  table.insert(order, name)
end

-- ====== Utils ======
local function clr(bg,fg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; if out.setTextColor then out.setTextColor(fg) end end
local function fill(x1,y1,x2,y2,bg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; for yy=y1,y2 do out.setCursorPos(x1,yy); out.write(string.rep(" ", x2-x1+1)) end end
local function writeAt(x,y,t,c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(x,y); out.write(t) end
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
  local name = s:match("%[(.-)%]")  -- capture zwischen [ ]
  if name and #name>0 then return name end
  return nil
end

-- ====== UI ======
local function header()
  fill(1,1,W,1,colors.gray); clr(colors.gray, colors.black)
  local ttl="Turtles"
  out.setCursorPos(math.max(1, math.floor((W-#ttl)/2))); out.write(ttl)
end

local function tabs()
  -- Zeile 2 = Tabs, in gleichbreite Segmente geteilt
  fill(1,2,W,2,colors.black)
  if #order==0 then return end
  local segW = math.max(3, math.floor(W / math.min(#order, 6))) -- max 6 tabs sichtbar
  local x = 1
  for i=1,math.min(#order, 6) do
    local name = order[i]
    local label = tostring(i) -- klein halten
    local sel = (i==activeIdx)
    clr(sel and colors.cyan or colors.lightGray, colors.black)
    local cx = x + math.floor((segW-#label)/2)
    out.setCursorPos(math.max(1,cx),2); out.write(label)
    x = x + segW
  end
end

local function footer()
  -- Vorletzte Zeile = Buttons kurz: P R S V
  local y = H-1
  if y < 4 then return end  -- superklein? dann nix
  fill(1,y,W,y,colors.black)
  local labels = { {"P", "pause", colors.lightBlue}, {"R","resume",colors.lime}, {"S","stop",colors.red}, {"V","verbose",colors.yellow} }
  local slot = math.floor(W/4)
  for i=1,4 do
    local x = (i-1)*slot + 2
    writeAt(x, y, labels[i][1], labels[i][3])
  end
end

local function viewTurtle(name)
  fill(1,3,W,H-2,colors.black)
  local t = turtles[name]
  if not t then
    writeAt(2,4,"Warte auf: "..(name or "?"), colors.yellow)
    return
  end

  -- Layout kompakt:
  -- Zeile 3: Name & Step
  writeAt(2,3, (name or "?"):sub(1, W-4), colors.white)
  -- Zeile 4: Fuel-Bar
  if H>=5 then
    local est=(t.length or 0)*35 + 150
    local lvl=(t.fuel=="unlimited") and est or tonumber(t.fuel) or 0
    writeAt(2,4,"F:", colors.white)
    bar(5,4, W-6, (est>0 and lvl/est or 0), colors.green, colors.yellow)
  end
  -- Zeile 5: Slots-Bar
  if H>=6 then
    local free=t.slotsFree or 16; local used=16-free
    writeAt(2,5,"S:", colors.white)
    bar(5,5, W-6, used/16, colors.lime, colors.orange)
  end
  -- Zeile 6: Progress
  if H>=7 then
    writeAt(2,6,"P:", colors.white)
    bar(5,6, W-6, ((t.step or 0)/math.max(1,(t.length or 1))), colors.blue, colors.yellow)
  end

  -- Chat-Box: letzte Zeile (oder zwei), je nach Hoehe
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

local function draw()
  header(); tabs()
  local name = order[activeIdx]
  if name then viewTurtle(name) else
    fill(1,3,W,H-2,colors.black); writeAt(2, math.max(3, math.floor(H/2)), "Warte auf Turtles...", colors.yellow)
  end
  footer()
end

-- ====== Control ======
local function sendCmd(name, cmd)
  if not name then return end
  local id = rednet.lookup("turtleCtl", name)
  if id then
    rednet.send(id, cmd, "turtleCtl")
  else
    rednet.broadcast({target=name, cmd=cmd}, "turtleCtl")
  end
end

-- ====== Event Loop ======
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
        if #c > 10 then table.remove(c,1) end
        turtles[who].chat = c
        draw()
      else
        -- Unbekannt -> lege in aktiven Tab ab
        local name = order[activeIdx]
        if name then
          turtles[name] = turtles[name] or {chat={}}
          local c = turtles[name].chat or {}
          c[#c+1] = s
          if #c > 10 then table.remove(c,1) end
          turtles[name].chat = c
          draw()
        end
      end
    end

  elseif ev[1]=="key" then
    local k = ev[2]
    if k==keys.left then if #order>0 then activeIdx=((activeIdx-2)%#order)+1; draw() end
    elseif k==keys.right then if #order>0 then activeIdx=(activeIdx%#order)+1; draw() end
    elseif k==keys.one or k==2 or k==3 or k==4 or k==5 or k==6 then
      local map={ [keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.four]=4,[keys.five]=5,[keys.six]=6 }
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
    -- Tabs (Zeile 2): in Segmente clustern
    if my==2 and #order>0 then
      local segW = math.max(3, math.floor(W / math.min(#order, 6)))
      local idx = math.floor((mx-1)/segW) + 1
      if idx>=1 and idx<=math.min(#order,6) then
        activeIdx = idx
        draw()
      end
    -- Buttons (vorletzte Zeile): 4 breite Zonen
    elseif my==H-1 and #order>0 then
      local slot = math.max(1, math.floor(W/4))
      local name = order[activeIdx]
      local idx = math.floor((mx-1)/slot) + 1
      if idx==1 then sendCmd(name,"pause")
      elseif idx==2 then sendCmd(name,"resume")
      elseif idx==3 then sendCmd(name,"stop")
      elseif idx==4 then sendCmd(name,"verbose")
      end
      draw()
    end

  elseif ev[1]=="timer" and ev[2]==timer then
    draw(); timer=os.startTimer(0.35)
  end
end
