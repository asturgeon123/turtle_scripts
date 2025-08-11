--[[
C&C Client v2.5
- Added 'home' command to return to a set position and direction
- Position & Direction Persistence
- Syncs with server's last known position on startup
]]

-- CONFIGURATION ------------------------------------------------
local serverHost = "http://127.0.0.1:5000"
local pollInterval = 5
local idFilePath = ".turtle_id"
local posFilePath = ".turtle_pos"
-----------------------------------------------------------------

local turtleId = 0
local position = {}
local homePosition = { x = 0, y = 0, z = 0, dir = 0 } -- Default home position
local directionVectors = {
    [0] = { x = 0, y = 0, z = -1 }, -- North
    [1] = { x = 1, y = 0, z = 0 },  -- East
    [2] = { x = 0, y = 0, z = 1 },  -- South
    [3] = { x = -1, y = 0, z = 0 }  -- West
}

-- FUNCTIONS ----------------------------------------------------

function httpPost(url, payload)
    local body = textutils.serializeJSON(payload)
    local response = http.post(url, body, {["Content-Type"] = "application/json"})
    if not response then return nil end
    local responseBody = response.readAll(); response.close()
    return textutils.unserializeJSON(responseBody)
end

function httpGet(url)
    local response = http.get(url)
    if not response then return nil end
    local responseBody = response.readAll(); response.close()
    return textutils.unserializeJSON(responseBody)
end

function savePosition()
    local file = fs.open(posFilePath, "w"); if file then file.write(textutils.serializeJSON(position)); file.close() end
end

function loadPosition()
    if fs.exists(posFilePath) then
        local file = fs.open(posFilePath, "r"); local data = file.readAll(); file.close()
        local decoded = textutils.unserializeJSON(data)
        if decoded and decoded.x and decoded.dir then
            position = decoded
            print(string.format("Loaded position: X:%d, Y:%d, Z:%d, Dir:%d", position.x, position.y, position.z, position.dir))
            return
        end
    end
    position = { x = 0, y = 0, z = 0, dir = 0 }
    savePosition()
end

function loadId()
    if fs.exists(idFilePath) then
        local file = fs.open(idFilePath, "r"); turtleId = file.readAll(); file.close()
        return turtleId ~= nil
    end
    return false
end

function registerWithServer()
    local responseData = httpPost(serverHost .. "/register", getStatus())
    if responseData and responseData.id then
        turtleId = responseData.id
        local file = fs.open(idFilePath, "w"); file.write(turtleId); file.close()
        return true
    end
    return false
end

function syncPositionWithServer()
    local serverPos = httpGet(serverHost .. "/get_position/" .. turtleId)
    if serverPos and serverPos.x ~= nil then
        position = { x = serverPos.x, y = serverPos.y, z = serverPos.z, dir = serverPos.dir }
        savePosition()
        print("Synced position with server.")
    end
end

function getStatus()
    local inventory = {}; for i=1,16 do local item = turtle.getItemDetail(i); if item then inventory[item.name] = (inventory[item.name] or 0) + item.count end end
    turtle.refuel()
    return { x = position.x, y = position.y, z = position.z, dir = position.dir, fuel = turtle.getFuelLevel(), inventory = inventory, }
end

function reportStatus() httpPost(serverHost .. "/update/" .. turtleId, getStatus()) end

-- SCAN FUNCTION
function scanEnvironment()
    local blocksData = {}
    local scanner = peripheral.find("geo_scanner")

    if scanner then
        print("GeoScanner found. Scanning...")
        local blocks, reason = scanner.scan(8) -- 3x3x3 scan
        if not blocks then
            print("Scan failed: " .. (reason or "Unknown error"))
            return false
        end

        for _, block in ipairs(blocks) do
            -- Convert relative scanner coordinates to absolute world coordinates
            local absX = position.x + block.x
            local absY = position.y + block.y
            local absZ = position.z + block.z
            local locationKey = string.format("%d,%d,%d", absX, absY, absZ)
            blocksData[locationKey] = block.name
        end
    else
        print("GeoScanner not found. Performing manual inspection...")
        -- Helper to add a block to the data table using an offset from the turtle's position
        local function addBlock(offset, blockInfo)
            -- This check prevents a "nil value" error if inspect() returns
            -- true but the blockInfo table is missing a name.
            if type(blockInfo) == "table" and blockInfo.name then
                local key = string.format("%d,%d,%d", position.x + offset.x, position.y + offset.y, position.z + offset.z)
                blocksData[key] = blockInfo.name
            end
        end

        -- Inspect Up and Down (no turning required)
        local upSuccess, upBlock = turtle.inspectUp()
        if upSuccess then addBlock({x=0, y=1, z=0}, upBlock) end

        local downSuccess, downBlock = turtle.inspectDown()
        if downSuccess then addBlock({x=0, y=-1, z=0}, downBlock) end

        -- Inspect Forward, Right, Back, and Left (requires turning)
        local originalDir = position.dir
        for i = 0, 3 do
            local currentFacingDir = (originalDir + i) % 4
            local facingVec = directionVectors[currentFacingDir]

            local success, block = turtle.inspect()
            if success then addBlock(facingVec, block) end

            if i < 3 then turn(turtle.turnLeft) end -- Turn for next inspection
        end
        -- Turn back to original direction
        turn(turtle.turnLeft)
        --position.dir = originalDir
        --faceDirection(originalDir)
    end

    print("Scan complete. Sending data to server...")
    httpPost(serverHost .. "/scan_report/" .. turtleId, {blocks = blocksData})
    os.sleep(0.5) -- Give the server a moment
    return true
end

function move(moveType)
    if turtle.getFuelLevel() < 1 then return false end
    if turtle[moveType]() then
        if moveType == "up" then position.y = position.y + 1 elseif moveType == "down" then position.y = position.y - 1 else
            local vec = directionVectors[position.dir]; local mult = (moveType == "forward") and 1 or -1
            position.x = position.x + (vec.x * mult); position.z = position.z + (vec.z * mult)
        end
        savePosition(); 
        reportStatus(); 
        scanEnvironment() -- Automatically scan after moving
        return true
    end
    return false
end

function turn(turnFunc)
    if turnFunc() then
        if turnFunc == turtle.turnLeft then position.dir = (position.dir - 1 + 4) % 4 else position.dir = (position.dir + 1) % 4 end
        savePosition(); reportStatus(); return true
    end
    return false
end

function faceDirection(targetDir)
    targetDir = tonumber(targetDir); if position.dir == targetDir then return true end
    local diff = (targetDir - position.dir + 4) % 4
    if diff == 1 then turn(turtle.turnRight) elseif diff == 2 then turn(turtle.turnRight); turn(turtle.turnRight) elseif diff == 3 then turn(turtle.turnLeft) end
    return position.dir == targetDir
end

-- GOTO FUNCTION
function goto(targetX, targetY, targetZ)
    targetX, targetY, targetZ = tonumber(targetX), tonumber(targetY), tonumber(targetZ)

    -- Handle vertical movement, digging if necessary
    while position.y ~= targetY do
        local direction = position.y < targetY and "up" or "down"
        if direction == "up" then
            if turtle.detectUp() and not turtle.digUp() then
                print("Failed to dig up.")
                return false
            end
        else -- direction is "down"
            if turtle.detectDown() and not turtle.digDown() then
                print("Failed to dig down.")
                return false
            end
        end
        if not move(direction) then
            print("Failed to move " .. direction)
            return false
        end
    end

    -- Handle horizontal movement
    local function clearAndMove() if turtle.detect() then if not turtle.dig() then return false end end; return move("forward") end
    while position.z > targetZ do faceDirection(0); if not clearAndMove() then return false end end
    while position.z < targetZ do faceDirection(2); if not clearAndMove() then return false end end
    while position.x > targetX do faceDirection(3); if not clearAndMove() then return false end end
    while position.x < targetX do faceDirection(1); if not clearAndMove() then return false end end
    return true
end

-- Function to go to the stored home position
function home()
    print("Navigating to home position: X:"..homePosition.x..", Y:"..homePosition.y..", Z:"..homePosition.z)
    local navigated = goto(homePosition.x, homePosition.y, homePosition.z)
    if navigated then
        print("Arrived at home location. Facing home direction: "..homePosition.dir)
        return faceDirection(homePosition.dir)
    else
        print("Failed to navigate to home location.")
        return false
    end
end

function sethome(x, y, z, dir)
    homePosition = { x = tonumber(x), y = tonumber(y), z = tonumber(z), dir = tonumber(dir or 0) }
    print("New home position set.")
    return true
end

function setpos(x, y, z, dir)
    position = { x = tonumber(x), y = tonumber(y), z = tonumber(z), dir = tonumber(dir) }
    savePosition(); reportStatus()
    return true
end

function executeCommand(cmd)
    print("Executing: " .. cmd)
    local parts = {}; for part in string.gmatch(cmd, "[^%s]+") do table.insert(parts, part) end
    local commandName = parts[1]; local args = { select(2, table.unpack(parts)) }
    if commandName == "home" then return home()
    elseif commandName == "goto" then return goto(table.unpack(args))
    elseif commandName == "setpos" then return setpos(table.unpack(args))
    elseif commandName == "sethome" then return sethome(table.unpack(args))
    elseif commandName == "forward" then return move("forward")
    elseif commandName == "back" then return move("back")
    elseif commandName == "up" then return move("up")
    elseif commandName == "down" then return move("down")
    elseif commandName == "turnLeft" then return turn(turtle.turnLeft)
    elseif commandName == "turnRight" then return turn(turtle.turnRight)
    elseif commandName == "faceDirection" then return faceDirection(table.unpack(args))
    elseif turtle[commandName] and type(turtle[commandName]) == "function" then return turtle[commandName]()
    else print("Unknown command: " .. cmd); return false end
end

-- MAIN LOGIC -------------------------------------------------

function startSequence()
    loadPosition()

    if loadId() then
        syncPositionWithServer()
    else
        while not registerWithServer() do os.sleep(5) end
    end

    reportStatus()
end



while true do
    print("Polling...")
    local response = httpPost(serverHost .. "/poll/" .. turtleId, getStatus())

    if response.error == "re-register" then
        print("Server error: re-register. Deleting local ID file.")
        fs.delete(".turtle_id") -- Deletes the .turtle_id file
        startSequence()
    end

    if response and response.commands and #response.commands > 0 then
        for _, cmd in ipairs(response.commands) do
            if not executeCommand(cmd) then print("Command failed, aborting batch."); reportStatus(); break end
            os.sleep(0.2)
        end
    end
    os.sleep(pollInterval)
end