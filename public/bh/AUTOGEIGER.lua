function Join(World)
  SendPacket(3, "action|join_request\nname|" .. World .. "|\ninvitedWorld|0")
end

function Drop(id)
  while GetItemCount(id) > 240 do
    SendPacket(2, "action|dialog_return\ndialog_name|drop\nitem_drop|"..id.."|\nitem_count|"..GetItemCount(id).."\n")
  end
end

function GetItemCount(id)
    for _, itm in pairs(GetInventory()) do
        if itm.id == id then
            return itm.amount
        end
    end
    return 0
end

function GetDroppedAmount(id)
  local ObjAmount = 0
  for _, obj in pairs(GetObjectList()) do
    if obj.id == id then
      ObjAmount = ObjAmount + obj.amount 
    end
  end
  return ObjAmount
end

function SendWebhook(url, data)
  MakeRequest(url, "POST", {
    ["Content-Type"] = "application/json"
  }, data)
end

function CleanStr(str)
  local cleanedStr = string.gsub(str, "`(%S)", '')
  cleanedStr = string.gsub(cleanedStr, "`{2}|(~{2})", '')
  return cleanedStr
end

function FormatNum(num)
  num = math.floor((num or 0) + 0.5)
  local formatted = tostring(num)
  local k = 3
  while k < #formatted do
    formatted = formatted:sub(1, #formatted - k) .. "," .. formatted:sub(#formatted - k + 1)
    k = k + 4
  end
  return formatted
end

function FormatTime(seconds)
  seconds = math.floor(seconds or 0)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%dh %dm %ds", h, m, s)
  elseif m > 0 then
    return string.format("%dm %ds", m, s)
  else
    return string.format("%ds", s)
  end
end

function Raw(t, s, v, x, y)
  SendPacketRaw(false, {
    type = t,
    state = s,
    value = v,
    x = x * 32,
    y = y * 32
  })
end

function PathFind(x, y)
    local PX = math.floor(GetLocal().pos.x / 32)
    local PY = math.floor(GetLocal().pos.y / 32)

    while math.abs(y - PY) > 6 do
        PY = PY + (y - PY > 0 and 6 or -6)
        FindPath(PX, PY)
        Sleep(200)
    end

    while math.abs(x - PX) > 6 do
        PX = PX + (x - PX > 0 and 6 or -6)
        FindPath(PX, PY)
        Sleep(200)
    end

    FindPath(x, y)
    Sleep(200)
end

function clamp(v, minV, maxV)
    local t = math.max(minV, math.min(v, maxV))
    if maxV <= 10 then return t end
    while v ~= t do
        v = v + (v < t and 1 or -1)
        Sleep(1000)
    end
    return v
end

function reconnect()
    while not GetWorld() or (GetWorld().name ~= Settings.World.Geiger) do
        Join(Settings.World.Geiger)
        Sleep(5000)
    end
end

function renewRing()
    while newRing == false do
        reconnect()
        Sleep(500)
    end
    newRing = false
end

-- init global variablr
redPosX = {5, 15, 25, 25, 15, 5}
redPosY = {5, 5, 5, 25, 25, 25}
listFound = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} -- Stuff, Black, Green, Red, White, Hchem, Rchem, Growtoken, Battery, D Battery, Charger
log = LogToConsole
red = 0
yellow = 1
green = 2
currentRing = red
newRing = false
itemFound = false
aliveGeiger = GetItemCount(2204)
totalFound = 0
canDrop = true
breakLoop = false
worldH, worldW = 53, 99

isStarting = false
isGeiger = false
isCharging = false
isTaking = false
isDropping = false
NeedWebhook = false


-- init packages
lantas = load(MakeRequest(
"https://raw.githubusercontent.com/lantas-bit/usefull/refs/heads/main/Findpath-algorithm",
"GET"
).content)()
Sleep(2000)

-- EditToggle("antibounce", true)
-- EditToggle("modfly", true)

function IsAdmin(AdminList, UserID)
  for _, AdminID in ipairs(AdminList) do
    if AdminID == UserID then
      return true
    end
  end
  return false
end

function genGrid()
  local UserID = GetLocal().userid
  local grid = {}

  for y = 0, worldH - 1 do
    grid[y] = {}
    for x = 0, worldW - 1 do
      local tile = GetTile(x, y)
      local blocked = true

      if tile then
        if (
          (tile.fg == 3796) or
          (tile.fg == 598 and tile.flags and tile.flags.enabled) or
          (tile.fg == 4352 and tile.flags and tile.flags.enabled) or
          (tile.fg == 1162) or
          (tile.fg == 16308 and tile.extra and IsAdmin(tile.extra.admin, UserID)) or
          (tile.fg == 3798 and tile.extra and IsAdmin(tile.extra.admin, UserID)) or
          (tile.coltype == 3 and tile.flags and tile.flags.public)
        ) then
          blocked = false
        elseif tile.coltype then
          blocked = tile.coltype > 0
        else
          blocked = false
        end

        if tile.fg ~= 0 and tile.fg ~= 9268 then
          blocked = true
        end
      else
        blocked = false
      end

      grid[y][x] = blocked and 1 or 0
    end

    if y >= 10 and y % 10 == 0 then
      Sleep(1)
    end
  end
  return grid
end

function isHasPath(tx, ty)
  local L = GetLocal()
  if not L or not L.pos then return false end

  local start = {x = L.pos.x // 32, y = L.pos.y // 32}
  local goal = {x = tx, y = ty}

  local path = lantas.findPath(start, goal, genGrid(), true)
  if not path or #path == 0 then return false end
  return path
end

function GetChargerPos()
  local Charger = {}
  for x = worldW, 0, -1 do
    for y = worldH, 0, -1 do
      if GetTile(x, y).fg == 4654 then
        table.insert(Charger, {x = x, y = y})
      end
    end
  end
  return Charger
end

function foundYellow()
    local foundPosX = GetLocal().pos.x // 32
    local foundPosY = GetLocal().pos.y // 32
    local currentLoc = 2
    local isLeft = false
    local isUp = false
    while true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29), Settings.Delay.FindPath)
            else
                PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29), Settings.Delay.FindPath)
            end
            breakLoop = false
            return
        end
        if itemFound == true then return end
        PathFind(clamp(foundPosX + currentLoc, 0, 29), foundPosY, Settings.Delay.FindPath)
        isLeft = false
        renewRing()
        if currentRing ~= yellow then break end
        PathFind(clamp(foundPosX + -currentLoc, 0, 29), foundPosY, Settings.Delay.FindPath)
        isLeft = true
        renewRing()
        if currentRing ~= yellow then break end
        currentLoc = currentLoc + 2
    end
    if currentRing == red then
        if isLeft == false then
            PathFind(clamp(GetLocal().pos.x // 32 + -12, 0, 29), foundPosY, Settings.Delay.FindPath)
            renewRing()
            if currentRing ~= green then
                if GetLocal().pos.y // 32 >= 20 then
                    PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -8, 0, 29), Settings.Delay.FindPath)
                else
                    PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 8, 0, 29), Settings.Delay.FindPath)
                end
                return
            end
        else
            PathFind(clamp(GetLocal().pos.x // 32 + 12, 0, 29), foundPosY, Settings.Delay.FindPath)
            renewRing()
            if currentRing ~= green then
                if GetLocal().pos.y // 32 >= 20 then
                    PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -8, 0, 29), Settings.Delay.FindPath)
                else
                    PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 8, 0, 29), Settings.Delay.FindPath)
                end
                return
            end
        end
        Sleep(10000)
    elseif currentRing == green then
        if isLeft == false then
            FindPath(clamp(GetLocal().pos.x // 32 + 4, 0, 29), foundPosY, Settings.Delay.FindPath)
        else
            FindPath(clamp(GetLocal().pos.x // 32 + -4, 0, 29), foundPosY, Settings.Delay.FindPath)
        end
        Sleep(10000)
    end
    foundPosX = GetLocal().pos.x // 32
    foundPosY = GetLocal().pos.y // 32
    currentLoc = 1
    while true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29), Settings.Delay.FindPath)
            else
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29), Settings.Delay.FindPath)
            end
            breakLoop = false
            return
        end
        if itemFound == true then return end
        FindPath(foundPosX, clamp(foundPosY + currentLoc, 0, 29), Settings.Delay.FindPath)
        isUp = false
        renewRing()
        if currentRing ~= green then break end
        FindPath(foundPosX, clamp(foundPosY + -currentLoc, 0, 29), Settings.Delay.FindPath)
        isUp = true
        renewRing()
        if currentRing ~= green then break end
        currentLoc = currentLoc + 1
    end
    if currentRing == yellow then
        if isUp == false then
            FindPath(foundPosX, clamp(GetLocal().pos.y // 32 + -5, 0, 29), Settings.Delay.FindPath)
        else
            FindPath(foundPosX, clamp(GetLocal().pos.y // 32 + 5, 0, 29), Settings.Delay.FindPath)
        end
        Sleep(10000)
    end
end

function foundGreen()
    local foundPosX = GetLocal().pos.x // 32
    local foundPosY = GetLocal().pos.y // 32
    local currentLocX = 1
    local isLeft = false
    local isUp = false
    while true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29), Settings.Delay.FindPath)
            else
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29), Settings.Delay.FindPath)
            end
            breakLoop = false
            return
        end
        if itemFound == true then return end
        FindPath(clamp(foundPosX + currentLocX, 0, 29), foundPosY, Settings.Delay.FindPath)
        isLeft = false
        renewRing()
        if currentRing ~= green then break end
        FindPath(clamp(foundPosX + -currentLocX, 0, 29), foundPosY, Settings.Delay.FindPath)
        isLeft = true
        renewRing()
        if currentRing ~= green then break end
        currentLocX = currentLocX + 1
    end
    if currentRing == yellow then
        if isLeft == false then
            FindPath(clamp(GetLocal().pos.x // 32 + -5, 0, 29), foundPosY, Settings.Delay.FindPath)
        else
            FindPath(clamp(GetLocal().pos.x // 32 + 5, 0, 29), foundPosY, Settings.Delay.FindPath)
        end
        Sleep(10000)
    end
    foundPosX = GetLocal().pos.x // 32
    foundPosY = GetLocal().pos.y // 32
    local currentLocY = 1
    while true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29), Settings.Delay.FindPath)
            else
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29), Settings.Delay.FindPath)
            end
            breakLoop = false
            return
        end
        if itemFound == true then return end
        FindPath(foundPosX, clamp(foundPosY + currentLocY, 0, 29), Settings.Delay.FindPath)
        isUp = false
        renewRing()
        if currentRing ~= green then break end
        FindPath(foundPosX, clamp(foundPosY + -currentLocY, 0, 29), Settings.Delay.FindPath)
        isUp = true
        renewRing()
        if currentRing ~= green then break end
        currentLocY = currentLocY + 1
    end
    if currentRing == yellow then
        if isUp == false then
            FindPath(foundPosX, clamp(GetLocal().pos.y // 32 + -5, 0, 29), Settings.Delay.FindPath)
        else
            FindPath(foundPosX, clamp(GetLocal().pos.y // 32 + 5, 0, 29), Settings.Delay.FindPath)
        end
        Sleep(10000)
    end
end

function ringHook(packet)
    if packet.type == 17 then
        if packet.xspeed == 2.00 then
            log("Green")
            currentRing = green
            newRing = true
        elseif packet.xspeed == 1.00 then
            log("Yellow")
            currentRing = yellow
            newRing = true
        else
            log("Red")
            currentRing = red
            newRing = true
        end
    end
end

World = string.upper(GetWorld().name)
Player = CleanStr(GetLocal().name):match("%S+")


function SendWebhook()
  local names = {
    "Stuff","Crystal Black","Crystal Green","Crystal Red","Crystal White",
    "Chemical Haunted","Chemical Radioactive","Growtoken","Battery","D Battery","Charger"
  }

  local found = ""
  for i, name in ipairs(names) do
    local amt = listFound[i] or 0
    if amt > 0 then
      if name:find("Crystal") then
        found = found .. "**" .. name .. " : " .. amt .. "**\n"
      else
        found = found .. name .. " : " .. amt .. "\n"
      end
    end
  end
  if found == "" then found = "No items found" end

  local data = '{ "embeds":[{ "title":"Geiger Scan Log", "color":11393254, "fields":[ ' ..
      '{"name":"Player","value":"' .. (Player or "Unknown") .. '","inline":false},' ..
      '{"name":"Items Found","value":"' .. found .. '","inline":true},' ..
      '{"name":"World","value":"' .. (World or "Unknown") .. '","inline":true} ] } ] }'

  MakeRequest(Settings.WebhookURL, "POST", { ["Content-Type"] = "application/json" }, data)
  NeedWebhook = false
end

function foundHook(varlist)
  if varlist[0]:find("OnConsoleMessage") and varlist[1]:find("oGiven") then
    if varlist[1]:find("Stuff") then
      listFound[1] = listFound[1] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("Crystal") then
      if varlist[1]:find("Black") then
        listFound[2] = listFound[2] + 1
        totalFound = totalFound + 1
      elseif varlist[1]:find("Green") then
        listFound[3] = listFound[3] + 1
        totalFound = totalFound + 1
      elseif varlist[1]:find("Red") then
        listFound[4] = listFound[4] + 1
        totalFound = totalFound + 1
      elseif varlist[1]:find("White") then
        listFound[5] = listFound[5] + 1
        totalFound = totalFound + 1
      end
    elseif varlist[1]:find("Haunted") then
      listFound[6] = listFound[6] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("Radioactive") then
      listFound[7] = listFound[7] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("Growtoken") then
      listFound[8] = listFound[8] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("`w1 Battery") then
      listFound[9] = listFound[9] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("D Battery") then
      listFound[10] = listFound[10] + 1
      totalFound = totalFound + 1
    elseif varlist[1]:find("Charger") then
      listFound[11] = listFound[11] + 1
      totalFound = totalFound + 1
    end
    log(string.format([[
Item Found : %d
Stuff : %d
Crystal Black : %d
Crystal Green : %d
Crystal Red : %d
Crystal White : %d
Chemical Haunted : %d
Chemical Radioactive : %d
Growtoken : %d
Battery : %d
D Battery : %d
Geiger Charger : %d
]], totalFound, listFound[1], listFound[2], listFound[3], listFound[4], listFound[5], listFound[6], listFound[7], listFound[8], listFound[9], listFound[10], listFound[11]))
    NeedWebhook = true
    itemFound = true
  end
  if varlist[0]:find("OnTextOverlay") and varlist[1]:find("You can't drop") then
    canDrop = false
  end
end

AddHook("onvariant", "lah", foundHook)
AddHook("onprocesstankupdatepacket", "haha", ringHook)

function fullAFK()
    SendPacket(2, "action|input\n|text|/warp "..Settings.World.Save.."\n")
    Sleep(5000)
    while GetWorld().name ~= Settings.World.Save do
        Sleep(5000)
        SendPacket(2, "action|input\n|text|/warp "..Settings.World.Save.."\n")
    end
    PathFind(Settings.Pos.AliveGeiger[1], Settings.Pos.AliveGeiger[2])

    Sleep(3000)
    local loop = true
    while loop == true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29))
            else
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29))
            end
            breakLoop = false
            return
        end
        loop = false
        PathFind(Settings.Pos.Valuable[1], Settings.Pos.Valuable[2])
        Sleep(500)
        for _,cur in pairs(GetInventory()) do
            if cur.id == 2242 or cur.id == 2244 or cur.id == 2246 or cur.id == 2248 or cur.id == 2250 or cur.id == 3306 or cur.id == 1962 or cur.id == 2206 or cur.id == 1482 then
                loop = true
                Sleep(500)
                SendPacket(2, "action|dialog_return\ndialog_name|drop\nitem_drop|"..cur.id.."|\nitem_count|"..cur.amount.."\n")
                Sleep(500)
                if canDrop == false then
                    itemDrop = itemDrop - 1
                end
            elseif cur.id == 1498 or cur.id == 1500 or cur.id == 2804 or cur.id == 2806 or cur.id == 15250 then
                SendPacket(2, "action|dialog_return\ndialog_name|trash\nitem_trash|"..cur.id.."|\nitem_count|"..cur.amount.."\n")
                Sleep(500)
                if canDrop == false then
                    itemDrop = itemDrop - 1
                end
            end
        end
      break
    end
    loop = true
    while loop == true do
        if breakLoop == true then
            if GetLocal().pos.y // 32 <= 15 then
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29))
            else
                FindPath(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29))
            end
            breakLoop = false
            return
        end
      break
    end
    SendPacket(2, "action|input\n|text|/warp "..Settings.World.Geiger.."\n")
    Sleep(5000)
    while GetWorld().name ~= Settings.World.Geiger do
        Sleep(5000)
        SendPacket(2, "action|input\n|text|/warp "..Settings.World.Geiger.."\n")
    end
end

function StartGeiger()
  if breakLoop == true then
        if GetLocal().pos.y // 32 <= 15 then
            PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + 15, 0, 29), Settings.Delay.FindPath)
        else
            PathFind(GetLocal().pos.x // 32, clamp(GetLocal().pos.y // 32 + -15, 0, 29), Settings.Delay.FindPath)
        end
        breakLoop = false
    end
    for i in pairs(redPosX) do
        if itemFound == true then 
            currentRing = red 
            break
        end
        if currentRing ~= red then break end
        FindPath(redPosX[i], redPosY[i], 500)
        renewRing()
    end
    if currentRing == yellow then
        foundYellow()
    elseif currentRing == green then
        foundGreen()
    end
    itemFound = false
    aliveGeiger = aliveGeiger - 1
    if aliveGeiger <= 5 then
        fullAFK()
        aliveGeiger = GetItemCount(2204)
    end
end

while true do
  if aliveGeiger <= 5 then
    SendPacket(2, "action|input\n|text|/warp "..Settings.World.Save.."\n")
    Sleep(5000)
    local path = isHasPath(Settings.Pos.AliveGeiger[1], Settings.Pos.AliveGeiger[2])
    if path then
      for _, step in ipairs(path) do
        FindPath(step.x, step.y)
        Sleep(300)
      end
    end
    PathFind(Settings.Pos.AliveGeiger[1], Settings.Pos.AliveGeiger[2])
    Sleep(500)
    Sleep(3000)
  end
  if GetItemCount(2286) > 240 then
    SendPacket(2, "action|input\n|text|/warp "..Settings.World.Save.."\n")
    Sleep(5000)
    if Settings.QoL.ChargeGeiger then
      local Chargers = GetChargerPos()
      for _, Total in pairs(Chargers) do
        local path = isHasPath(Total.x, Total.y)
        if path then
          for _, step in ipairs(path) do
            FindPath(step.x, step.y)
            Sleep(400)
          end
          Raw(3, 0, 2268, Total.x, Total.y)
          Sleep(600)
        end
        Sleep(400)
      end
    end
    if Settings.QoL.DropGeiger then
      local path = isHasPath(Settings.Pos.DeadGeiger[1], Settings.Pos.DeadGeiger[2])
      if path then
        for _, step in ipairs(path) do
          FindPath(step.x, step.y)
          Sleep(400)
        end
        Drop(2286)
        SendPacket(2, "action|dialog_return\ndialog_name|drop\nitem_drop|2286|\nitem_count|"..GetItemCount(2286).."\n")
      end
      PathFind(Settings.Pos.DeadGeiger[1], Settings.Pos.DeadGeiger[2])
      Sleep(500)
      SendPacket(2, "action|dialog_return\ndialog_name|drop\nitem_drop|2286|\nitem_count|"..GetItemCount(2286).."\n")
    end
  end
  if GetItemCount(2204) > 5 then
    reconnect()
    if NeedWebhook then
      SendWebhook()
      NeedWebhook = false
    end
    StartGeiger()
  end
end

--[[
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
ORIGINAL BY Swipez#8871 Or hola_senor AKA Swipez
]]
    

