-- turtleMonitor.lua
-- Zeigt alle Sprüche der Turtle live auf Monitor

rednet.open("left") -- anpassen je nach Modemseite
term.clear()
term.setCursorPos(1,1)
print("🐢 Turtle Live-Feed")

while true do
  local id, msg, prot = rednet.receive("turtleChat")
  term.scroll(1)
  local x, y = term.getCursorPos()
  term.setCursorPos(1, y)
  print(msg)
end
