-- turtle.lua
local modem = peripheral.find("ender_modem")
if not modem then error("Kein Ender Modem gefunden!") end

local side = peripheral.getName(modem)
if not rednet.isOpen(side) then
  rednet.open(side)
end

print("Turtle online. Warte auf Befehle...")

while true do
  local id, msg, proto = rednet.receive("tunnel54")
  if type(msg) == "string" then
    print("Befehl empfangen:", msg)

    if msg == "forward" then turtle.forward() end
    if msg == "back" then turtle.back() end
    if msg == "up" then turtle.up() end
    if msg == "down" then turtle.down() end
    if msg == "left" then turtle.turnLeft() end
    if msg == "right" then turtle.turnRight() end
    if msg == "stop" then print("Stop-Befehl erhalten.") end
  end
end
