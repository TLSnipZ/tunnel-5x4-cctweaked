-- turtleMonitorMulti.lua (v4 – Rich, Fixed Scale, Log+Chat getrennt)
-- - Kein Autoscale; feste fette UI (stell Monitor groß genug hin, textScale=0.5)
-- - Multi-Turtle Tabs (Ender via rednet)
-- - Detaillierte Panels (Fuel/Slots/Progress/Details)
-- - Unten zwei Boxen: Log (turtleLog, immer an) + Chat (turtleChat, Funny/Verbose)
-- - Hotkeys: ← → Tabs / 1..9 Direkt / P R S V / Q / F5 / PageUp/Down (Log) / [ ] (Chat)

---------------------- CONFIG ----------------------
local TEXT_SCALE = 0.5
local MIN_COLS   = 70
local MIN_ROWS   = 18
local CHAT_LINES = 6
local MAX_CHAT_KEEP = 200

---------------------- MONITOR ---------------------
local mon = peripheral.find("monitor")
local out = mon or term
if mon then mon.setTextScale(TEXT_SCALE) end
local W,H = out.getSize()

---------------------- MODEMS ----------------------
for _,side in ipairs(rs.getSides()) do
  if peripheral.getType(side)=="modem" then pcall(rednet.open, side) end
end

---------------------- STATE -----------------------
-- turtles[name] = { fuel, needHome, step, length, col, width, dir, slotsFree,
--                   lastSeen, chatFun={}, chatLog={}, chatOffFun=0, chatOffLog=0 }
local turtles = {}
local order = {}
local activeIdx = 1
local function ensureInOrder(name) for i=1,#order do if order[i]==name then return end end; table.insert(order,name) end

---------------------- UTILS -----------------------
local function clr(bg,fg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; if out.setTextColor then out.setTextColor(fg) end end
local function fill(x1,y1,x2,y2,bg) if out.setBackgroundColor then out.setBackgroundColor(bg) end; for y=y1,y2 do out.setCursorPos(x1,y); out.write(string.rep(" ", x2-x1+1)) end end
local function writeAt(x,y,t,c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(x,y); out.write(t) end
local function center(y, txt, c) if c and out.setTextColor then out.setTextColor(c) end; out.setCursorPos(math.max(1, math.floor((W-#txt)/2)), y); out.write(txt) end
local function bar(x,y,wid,ratio,okColor,warnColor)
  ratio=math.max(0,math.min(1,ratio or 0)); local fillw=math.floor(wid*ratio+0.5)
  clr(colors.gray, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", wid))
  local c=(ratio<0.2) and colors.red or ((ratio<0.45) and warnColor or okColor)
  clr(c, colors.black); out.setCursorPos(x,y); out.write(string.rep(" ", fillw))
end
local function parseNameFromChat(s) if type(s)~="string" then return nil end; local n=s:match("%[(.-)%]"); if n and #n>0 then return n end; return nil end
local function pushChatFun(name, line) turtles[name]=turtles[name] or {}; local c=turtles[name].chatFun or {}; c[#c+1]=line; if #c>MAX_CHAT_KEEP then table.remove(c,1) end; turtles[name].chatFun=c end
local function pushChatLog(name, line) turtles[name]=turtles[name] or {}; local c=turtles[name].chatLog or {}; c[#c+1]=line; if #c>MAX_CHAT_KEEP then table.remove(c,1) end; turtles[name].chatLog=c end

---------------------- HEADER/TABS/FOOTER ----------
local buttons = {
  {label="[P]ause",   x1=2,  x2=10, color=colors.lightBlue, cmd="pause"},
  {label="[R]esume",  x1=14, x2=23, color=colors.lime,      cmd="resume"},
  {label="[S]top",    x1=27, x2=34, color=colors.red,       cmd="stop"},
  {label="[V]erbose", x1=38, x2=48, color=colors.yellow,    cmd="verbose"},
}
local function header()
  fill(1,1,W,1,colors.gray); clr(colors.gray, colors.black)
  center(1, "🐢 Turtle Monitor (Ender) | Tabs: 1..9/←→ | P R S V | PgUp/Dn Log  [ ] Chat | Q", colors.black)
  if W<MIN_COLS or H<MIN_ROWS then writeAt(2,2,"Hinweis: Monitor < empfohlen ("..MIN_COLS.."x"..MIN_ROWS..")", colors.yellow) end
end
local function tabs()
  fill(1,3,W,3,colors.black)
  local x=2
  for i,name in ipairs(order) do
    local lab=(" %d:%s "):format(i,name)
    if x+#lab>W-2 then break end
    clr((i==activeIdx) and colors.cyan or colors.lightGray, colors.black)
    out.setCursorPos(x,3); out.write(lab)
    x=x+#lab+1
  end
end
local function footer() local y=H-1; fill(1,y,W,H,colors.black); for _,b in ipairs(buttons) do writeAt(b.x1,y,b.label,b.color) end; writeAt(W-15,y,"F5 Refresh",colors.lightGray) end

---------------------- VIEW ------------------------
local function viewTurtle(name)
  fill(1,4,W,H-2,colors.black)
  local t=turtles[name]
  if not t then writeAt(2,6,"Warte auf Turtle: "..(name or "?"), colors.yellow); return end

  writeAt(2,4,("Turtle: %s"):format(name), colors.white)
  writeAt(W-20,4,os.date and os.date("%H:%M:%S") or "", colors.lightGray)

  -- Fuel
  local est=(t.length or 0)*35 + 150
  local lvl=(t.fuel=="unlimited") and est or tonumber(t.fuel) or 0
  writeAt(2,6,"Fuel:",colors.white); bar(10,6,W-12,(est>0 and lvl/est or 0),colors.green,colors.yellow)
  writeAt(2,7,("Level: %s   Heimweg: %d   Empfehlung: ~%d"):format(tostring(t.fuel), t.needHome or 0, est), colors.lightGray)

  -- Slots
  local free=t.slotsFree or 16; local used=16-free
  writeAt(2,9,"Slots:",colors.white); bar(10,9,W-12, used/16, colors.lime, colors.orange)
  writeAt(2,10,("Frei: %d   Belegt: %d/16"):format(free, used), colors.lightGray)

  -- Progress
  local prog=((t.step or 0)/math.max(1,(t.length or 1)))
  writeAt(2,12,"Progress:",colors.white); bar(12,12,W-14, prog, colors.blue, colors.yellow)
  writeAt(2,13,("Step: %d / %d   Spalte: %d/%d   Richtung: %s"):format(t.step or 0,t.length or 0,t.col or 1,t.width or 5,t.dir or "?"), colors.lightGray)

  -- Extra rechts
  local rx=math.max(2, math.floor(W*0.58))
  writeAt(rx,6,"Details:",colors.white)
  writeAt(rx,7,("NeedHome: %d"):format(t.needHome or 0), colors.lightGray)
  writeAt(rx,8,("FuelLevel: %s"):format(tostring(t.fuel)), colors.lightGray)
  writeAt(rx,9,("SlotsFree: %d"):format(free), colors.lightGray)
  writeAt(rx,10,("Direction: %s"):format(t.dir or "?"), colors.lightGray)
  writeAt(rx,11,("Width: %d  Col: %d"):format(t.width or 5, t.col or 1), colors.lightGray)
  writeAt(rx,12,("Length: %d  Step: %d"):format(t.length or 0, t.step or 0), colors.lightGray)

  -- Log + Chat (unten)
  local pad = CHAT_LINES
  local padLog = math.max(2, math.floor(pad*0.6))
  local padFun = math.max(2, pad - padLog)
  local yLogTop = H - 2 - (padLog + padFun)
  local yFunTop = yLogTop + padLog + 1

  -- Log
  fill(1,yLogTop-1,W,yLogTop-1,colors.gray); clr(colors.gray, colors.black); writeAt(2,yLogTop-1," Log (Steps) – PgUp/PgDn ",colors.black)
  do
    clr(colors.black, colors.lightGray)
    local c=t.chatLog or {}; t.chatOffLog=t.chatOffLog or 0
    local off=math.max(0, math.min(t.chatOffLog, math.max(0,#c-padLog)))
    for i=0,padLog-1 do
      local idx=#c-off-(padLog-1-i); local msg=c[idx] or ""
      local txt=tostring(msg):gsub("\n"," "); if #txt>W-2 then txt=txt:sub(1,W-5).."..." end
      writeAt(2,yLogTop+i,txt,colors.lightGray)
    end
  end

  -- Chat
  fill(1,yFunTop-1,W,yFunTop-1,colors.gray); clr(colors.gray, colors.black); writeAt(2,yFunTop-1," Chat (Verbose/Funny) – [ ] scroll ",colors.black)
  do
    clr(colors.black, colors.lightGray)
    local c=t.chatFun or {}; t.chatOffFun=t.chatOffFun or 0
    local off=math.max(0, math.min(t.chatOffFun, math.max(0,#c-padFun)))
    for i=0,padFun-1 do
      local idx=#c-off-(padFun-1-i); local msg=c[idx] or ""
      local txt=tostring(msg):gsub("\n"," "); if #txt>W-2 then txt=txt:sub(1,W-5).."..." end
      writeAt(2,yFunTop+i,txt,colors.lightGray)
    end
  end
end

---------------------- CONTROL ---------------------
local function sendCmd(name, cmd)
  if not name then return end
  local id=rednet.lookup("turtleCtl",name)
  if id then rednet.send(id,cmd,"turtleCtl") else rednet.broadcast({target=name,cmd=cmd},"turtleCtl") end
end

---------------------- RENDER ----------------------
local function draw() header(); tabs(); local name=order[activeIdx]; if name then viewTurtle(name) else fill(1,4,W,H-2,colors.black); writeAt(2, math.max(5, math.floor(H/2)), "Warte auf Turtles...", colors.yellow) end; footer() end

---------------------- LOOP ------------------------
out.setBackgroundColor(colors.black); out.clear(); draw()
local timer=os.startTimer(0.35)

while true do
  local ev={ os.pullEvent() }

  if ev[1]=="rednet_message" then
    local _, msg, proto = ev[2], ev[3], ev[4]

    if proto=="turtleStatus" then
      local data = (type(msg)=="table") and msg or (textutils.unserialize(msg) or (textutils.unserializeJSON and textutils.unserializeJSON(msg)))
      if type(data)=="table" and data.type=="status" and data.name then
        local t=turtles[data.name] or {chatFun={},chatLog={},chatOffFun=0,chatOffLog=0}
        for k,v in pairs(data) do if k~="type" then t[k]=v end end
        t.lastSeen=os.time(); turtles[data.name]=t; ensureInOrder(data.name); draw()
      end

    elseif proto=="turtleChat" then
      local s=tostring(msg or ""); local who=parseNameFromChat(s) or order[activeIdx]; if who then pushChatFun(who,s); draw() end

    elseif proto=="turtleLog" then
      local s=tostring(msg or ""); local who=parseNameFromChat(s) or order[activeIdx]; if who then pushChatLog(who,s); draw() end

    end

  elseif ev[1]=="key" then
    local k=ev[2]
    if k==keys.left then if #order>0 then activeIdx=((activeIdx-2)%#order)+1; draw() end
    elseif k==keys.right then if #order>0 then activeIdx=(activeIdx%#order)+1; draw() end
    elseif k==keys.one or k==keys.two or k==keys.three or k==keys.four or k==keys.five or k==keys.six or k==keys.seven or k==keys.eight or k==keys.nine then
      local map={ [keys.one]=1,[keys.two]=2,[keys.three]=3,[keys.four]=4,[keys.five]=5,[keys.six]=6,[keys.seven]=7,[keys.eight]=8,[keys.nine]=9 }
      local idx=map[k]; if idx and order[idx] then activeIdx=idx; draw() end
    elseif k==keys.q then break
    elseif k==keys.p then if order[activeIdx] then sendCmd(order[activeIdx],"pause") end
    elseif k==keys.r then if order[activeIdx] then sendCmd(order[activeIdx],"resume") end
    elseif k==keys.s then if order[activeIdx] then sendCmd(order[activeIdx],"stop") end
    elseif k==keys.v then if order[activeIdx] then sendCmd(order[activeIdx],"verbose") end
    elseif k==keys.pageUp then local name=order[activeIdx]; if name and turtles[name] then local t=turtles[name]; t.chatOffLog=math.min((t.chatOffLog or 0)+3, math.max(0, #(t.chatLog or {})-CHAT_LINES)); draw() end
    elseif k==keys.pageDown then local name=order[activeIdx]; if name and turtles[name] then local t=turtles[name]; t.chatOffLog=math.max((t.chatOffLog or 0)-3, 0); draw() end
    elseif k==keys.rightBracket then local name=order[activeIdx]; if name and turtles[name] then local t=turtles[name]; t.chatOffFun=math.min((t.chatOffFun or 0)+3, math.max(0, #(t.chatFun or {})-CHAT_LINES)); draw() end
    elseif k==keys.leftBracket  then local name=order[activeIdx]; if name and turtles[name] then local t=turtles[name]; t.chatOffFun=math.max((t.chatOffFun or 0)-3, 0); draw() end
    elseif k==keys.f5 then draw() end

  elseif ev[1]=="mouse_click" then
    local _, mx, my = ev[2], ev[3], ev[4]
    if my==3 and #order>0 then
      local x=2; for i,name in ipairs(order) do local lab=(" %d:%s "):format(i,name); local x2=x+#lab-1; if mx>=x and mx<=x2 then activeIdx=i; draw(); break end; x=x+#lab+1; if x>W-2 then break end end
    elseif my==H-1 and #order>0 then
      local name=order[activeIdx]
      for _,b in ipairs(buttons) do if mx>=b.x1 and mx<=b.x2 then sendCmd(name,b.cmd); draw(); break end end
    end

  elseif ev[1]=="monitor_touch" then
    local _, mx, my = ev[2], ev[3], ev[4]
    if my==3 and #order>0 then
      local x=2; for i,name in ipairs(order) do local lab=(" %d:%s "):format(i,name); local x2=x+#lab-1; if mx>=x and mx<=x2 then activeIdx=i; draw(); break end; x=x+#lab+1; if x>W-2 then break end end
    elseif my==H-1 and #order>0 then
      local name=order[activeIdx]
      for _,b in ipairs(buttons) do if mx>=b.x1 and mx<=b.x2 then sendCmd(name,b.cmd); draw(); break end end
    end

  elseif ev[1]=="timer" and ev[2]==timer then draw(); timer=os.startTimer(0.35) end
end
