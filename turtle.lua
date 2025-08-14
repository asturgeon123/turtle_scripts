

--[[
C&C Client v2.6
- Added 'home' command to return to a set position and direction
- Position & Direction Persistence
- Syncs with server's last known position on startup
- Reports current job in status
- Added 'cancel' command to stop the current job
]]

-- CONFIGURATION ------------------------------------------------
local serverHost = "http://192.168.1.71:5000"
local pollInterval = 5
local idFilePath = ".turtle_id"
local posFilePath = ".turtle_pos"

-- World height constants for modern Minecraft
local SCAN_TOP = 70 -- The highest buildable block is Y=319.
local SCAN_BOTTOM = -63 -- The lowest buildable block/bedrock layer starts at Y=-64.

local enderChestName ='enderstorage:ender_chest'
local CHEST_NAMES = {'minecraft:chest', 'minecraft:ender_chest', enderChestName}


-- List of essential items the turtle should not drop.
-- You can add or remove items here (e.g., fuel).
local essentialItems = {
    ["computercraft:wireless_modem_normal"] = true,
    ["computercraft:wireless_modem_advanced"] = true,
    ["minecraft:diamond_pickaxe"] = true,
    ["advancedperipherals:geo_scanner"] = true,
    ["minecraft:ender_chest"] = true,
    [enderChestName] = true,
}


--- END CONFIGURATION -------------------------------------------

local turtleId = 0
local position = {}
local homePosition = { x = 0, y = 0, z = 0, dir = 0 } -- Default home position
local directionVectors = {
    [0] = { x = 0, y = 0, z = -1 }, -- North
    [1] = { x = 1, y = 0, z = 0 },  -- East
    [2] = { x = 0, y = 0, z = 1 },  -- South
    [3] = { x = -1, y = 0, z = 0 }  -- West
}
local currentJob = "idle"
local cancelCurrentJob = false

-- API FUNCTIONS ----------------------------------------------------
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
    enderUnloadInventory()
    local equipment = {turtle.getEquippedLeft()['name'], turtle.getEquippedRight()['name']}
    return { x = position.x, y = position.y, z = position.z, dir = position.dir, fuel = turtle.getFuelLevel(), inventory = inventory, equipment=equipment, current_job = currentJob}
end

function reportStatus()
    httpPost(serverHost .. "/update/" .. turtleId, getStatus())
end
-- END API FUNCTIONS ----------------------------------------------------


-- ITEM MANAGEMENT FUNCTIONS ----------------------------------------------


function enderUnloadInventory(override)
-- If the inventory is full, place an enderchest and unload.

    local sucess = true
    override = false or override
    if isInventoryFull() or override then
        print("Inventory is full. UNLOADING")
        local start_position = position
        
        -- Equipment the item to mine the chest first.
        if not equipItem("minecraft:diamond_pickaxe") then
            return false
        end

        if not placeEnderChest() then
            return false
        end


        os.sleep(2)



        transferToChest()

        if not turtle.dig() then
            return false
        end

        if not faceDirection(position.dir) then
            return false
        end

    end

    



end
---
-- Checks if the inventory is considered full.
-- @param maxFilledSlots (optional) The number of slots that must be filled for the inventory to be "full". Defaults to 15.
-- @return boolean True if the number of filled slots is greater than or equal to maxFilledSlots.
---
function isInventoryFull(maxFilledSlots)
    -- Defaults to 15 to leave one slot open for maneuvering items or picking up a single new item.
    maxFilledSlots = maxFilledSlots or 15
    local filledSlots = 0
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            filledSlots = filledSlots + 1
        end
    end
    return filledSlots >= maxFilledSlots
end


function transferToChest()
    ---
    -- Transfers all non-essential items to an container in front of turtle.
    -- @return boolean True if at least one item was successfully transferred.
    ---
    local transferredSomething = false
    local originalSlot = turtle.getSelectedSlot()

    local chest = nil
    for index, chest_name in ipairs(CHEST_NAMES) do
        print(chest_name)
        chest = peripheral.find(chest_name)
        if chest then
            print("Found chest ".. chest_name)
            break
        end
    end

    

    if chest then
        -- Iterate over all inventory slots

        for i = 1, 16 do
            local item = turtle.getItemDetail(i)
            if item and not essentialItems[item.name] then
                turtle.select(i)
                local item_dropped, reason = turtle.drop()
                if item_dropped then
                    transferredSomething = true
                else
                    print(reason)
                    print("Could not drop item. Target inventory might be full.")
                    break -- Stop if chest is full
                end
            end
        end
    else
        print("Chest not found")
    end

    turtle.select(originalSlot) -- Restore the originally selected slot
    if not transferredSomething then
        print("Nothing transferred. Is the inventory full?")
    end

    reportStatus()

    return transferredSomething
end

---
-- Finds an ender chest in the inventory and places it on the block below the turtle.
-- @return boolean True if the ender chest was successfully placed.
---
function placeEnderChest()
    local originalSlot = turtle.getSelectedSlot()

    -- Find the ender chest in the inventory
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == enderChestName then
            turtle.select(i)

            -- Attempt to place the chest down.
            local count = 1
            while count <= 4 do

                local block_infront = turtle.detect()
                if not block_infront then
                    turtle.place()
                    return true
                else
                    turtle.turnRight()
                end
                count = count + 1
            end

            turtle.dig()
            turtle.place()
            return true
        end
    end

    print("Ender Chest not found in inventory.")
    turtle.select(originalSlot) -- Restore original slot even on failure
    return false
end

function equipItem(toolName)

    -- Items to equip
    -- computercraft:wireless_modem_normal
    -- minecraft:diamond_pickaxe
    -- advancedperipherals:geo_scanner

    -- Check if the item is already equipped
    local equippedLeft = turtle.getEquippedLeft()
    print(equippedLeft)
    if equippedLeft and equippedLeft.name == toolName then
        print("Tool '" .. toolName .. "' is already equipped.")
        return true
    end


    -- Find the tool in the inventory
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == toolName then
            turtle.select(i)
            if turtle.equipLeft() then
                print("Successfully equipped '" .. toolName .. "'.")
                reportStatus()
                return true
            else
                -- If equipping left fails, it might be because something is already there.
                -- Let's try the right side as a fallback.
                if turtle.equipRight() then
                    print("Successfully equipped '" .. toolName .. "' to right hand.")
                    reportStatus()
                    return true
                else
                    print("Failed to equip '" .. toolName .. "' to either hand.")
                    turtle.select(1) -- Reselect first slot as a default
                    return false
                end
            end
        end
    end

    print("Tool '" .. toolName .. "' not found in inventory.")
    return false
end

-- END MANAGEMENT FUNCTIONS ----------------------------------------------

-- PERSISTENCE FUNCTIONS ----------------------------------------------------
function savePosition()
    local file = fs.open(posFilePath, "w"); if file then file.write(textutils.serializeJSON(position)); file.close() end
end

function getGPSPos()
    --- Determines direction by moving into an open block to see how the position changed. Sets the intial position

    
    equipItem("computercraft:wireless_modem_advanced")
    

    local start_x, start_y, start_z = gps.locate()
    local direction = nil
    
    if start_x and start_y and start_z then
        -- GPS Aquired
        -- Check for an empty block to move into

        local count = 1
        while count <= 4 do
            print("Checking direction:", count)

            local block_infront = turtle.detect()
            if not block_infront then
                turtle.forward()
                local end_x, end_y, end_z = gps.locate()
                turtle.back()

                if end_x and end_y and end_z then
                    -- Check difference between start and end

                    local diff_x = end_x - start_x
                    local diff_z = end_z - start_z

                    -- Iterate through the direction vectors to find the one that matches the change in coordinates.
                    for i, vec in pairs(directionVectors) do
                        if vec.x == diff_x and vec.z == diff_z then
                            direction = i
                            print("Direction Found,", direction)
                            setpos(start_x, start_y, start_z, direction)
                            break
                        end
                    end

                    break
                end
                
            else
                turtle.turnRight()
            end
            count = count + 1
        end

        return true
   else
       return false
   end

    
end

function loadPosition()
    if fs.exists(posFilePath) then
        local file = fs.open(posFilePath, "r"); local data = file.readAll(); file.close()
        local decoded = textutils.unserializeJSON(data)
        if decoded and decoded.x and decoded.dir then
            position = decoded
            print(string.format("Loaded position: X:%d, Y:%d, Z:%d, Dir:%d", position.x, position.y, position.z, position.dir))
            return true
        end
    end
    position = { x = 0, y = 0, z = 0, dir = 0 }
    savePosition()
    return false
end

function loadId()
    if fs.exists(idFilePath) then
        local file = fs.open(idFilePath, "r")
        local idString = file.readAll()
        file.close()
        local idNumber = tonumber(idString)
        if idNumber and idNumber > 0 then
            turtleId = idNumber
            return true
        end
    end
    return false
end

-- END PERSISTENCE FUNCTIONS ----------------------------------------------------







-- MULTI STEP ACTION FUNCTIONS ----------------------------------------------------
function scanEnvironment()
    if checkCancel() then return false end
    local blocksData = {}
    
    equipItem("advancedperipherals:geo_scanner")

    local scanner = peripheral.find("geo_scanner")

    if scanner then
        print("GeoScanner found. Scanning...")
        local blocks, reason = scanner.scan(8)
        if not blocks then
            print("Scan failed: " .. (reason or "Unknown error"))
            return false
        end

        for _, block in ipairs(blocks) do
            local absX = position.x + block.x
            local absY = position.y + block.y
            local absZ = position.z + block.z
            local locationKey = string.format("%d,%d,%d", absX, absY, absZ)
            blocksData[locationKey] = block.name
        end
    else
        print("GeoScanner not found. Performing manual inspection...")
        local function addBlock(offset, blockInfo)
            if type(blockInfo) == "table" and blockInfo.name then
                local key = string.format("%d,%d,%d", position.x + offset.x, position.y + offset.y, position.z + offset.z)
                blocksData[key] = blockInfo.name
            end
        end

        local upSuccess, upBlock = turtle.inspectUp()
        if upSuccess then addBlock({x=0, y=1, z=0}, upBlock) end

        local downSuccess, downBlock = turtle.inspectDown()
        if downSuccess then addBlock({x=0, y=-1, z=0}, downBlock) end

        local originalDir = position.dir
        for i = 0, 3 do
            if checkCancel() then return false end
            local currentFacingDir = (originalDir + i) % 4
            local facingVec = directionVectors[currentFacingDir]

            local success, block = turtle.inspect()
            if success then addBlock(facingVec, block) end

            if i < 3 then turn(turtle.turnLeft) end
        end
        turn(turtle.turnLeft)
    end

    print("Scan complete. Sending data to server...")
    httpPost(serverHost .. "/scan_report/" .. turtleId, {blocks = blocksData})
    os.sleep(0.5)
    return true
end

function scanChunk()
    currentJob = "scanning chunk"
    reportStatus()
    print("Starting chunk scan.")

    local chunkX = math.floor(position.x / 16)
    local chunkZ = math.floor(position.z / 16)
    local centerX = chunkX * 16 + 7
    local centerZ = chunkZ * 16 + 7

    print("Navigating to chunk center: X:"..centerX..", Z:"..centerZ)
    if not goto(centerX, SCAN_TOP, centerZ) then
        print("Failed to navigate to chunk center. Aborting scan.")
        currentJob = "idle"
        return false
    end

    print("Moving to bedrock level (Y:"..SCAN_BOTTOM..")...")
    if not goto(centerX, SCAN_BOTTOM, centerZ) then
        print("Failed to navigate to chunk center. Aborting scan.")
        currentJob = "idle"
        return false
    end
    print("Reached bottom scan level.")

    print("Chunk scan complete.")
    currentJob = "idle"
    return true
end

function home()
    currentJob = "going home"
    reportStatus()
    print("Navigating to home position: X:"..homePosition.x..", Y:"..homePosition.y..", Z:"..homePosition.z)
    local navigated = goto(homePosition.x, homePosition.y, homePosition.z)
    if navigated then
        print("Arrived at home location. Facing home direction: "..homePosition.dir)
        local result = faceDirection(homePosition.dir)
        currentJob = "idle"
        return result
    else
        print("Failed to navigate to home location.")
        currentJob = "idle"
        return false
    end
end
-- END ACTION FUNCTIONS ----------------------------------------------------








-- MOVEMENT FUNCTIONS ----------------------------------------------------

function move(moveType)
    if checkCancel() then return false end
    if turtle.getFuelLevel() < 1 then return false end
    if turtle[moveType]() then
        if moveType == "up" then position.y = position.y + 1 elseif moveType == "down" then position.y = position.y - 1 else
            local vec = directionVectors[position.dir]; local mult = (moveType == "forward") and 1 or -1
            position.x = position.x + (vec.x * mult); position.z = position.z + (vec.z * mult)
        end
        savePosition();
        reportStatus();
        scanEnvironment()
        return true
    end
    return false
end

function turn(turnFunc)
    if checkCancel() then return false end
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

function goto(targetX, targetY, targetZ)
    currentJob = "going to " .. targetX .. "," .. targetY .. "," .. targetZ
    reportStatus()
    targetX, targetY, targetZ = tonumber(targetX), tonumber(targetY), tonumber(targetZ)

    -- Vertical Movement
    while position.y ~= targetY do
        if checkCancel() then currentJob = "idle"; return false end
        equipItem("minecraft:diamond_pickaxe")
        local direction = position.y < targetY and "up" or "down"
        if direction == "up" then
            if turtle.detectUp() and not turtle.digUp() then
                print("Failed to dig up.")
                currentJob = "idle"
                return false
            end
        else
            if turtle.detectDown() and not turtle.digDown() then
                print("Failed to dig down.")
                currentJob = "idle"
                return false
            end
        end
        if not move(direction) then
            print("Failed to move " .. direction)
            currentJob = "idle"
            return false
        end
    end

    local function clearAndMove() 
        if checkCancel() then 
            return false 
        end; 
        if turtle.detect() then 
            equipItem("minecraft:diamond_pickaxe")
            if not turtle.dig() then 
                return false
         end
        end; 
        return move("forward") 
    end

    
    while position.z > targetZ do if not faceDirection(0) or not clearAndMove() then currentJob = "idle"; return false end end
    while position.z < targetZ do if not faceDirection(2) or not clearAndMove() then currentJob = "idle"; return false end end
    while position.x > targetX do if not faceDirection(3) or not clearAndMove() then currentJob = "idle"; return false end end
    while position.x < targetX do if not faceDirection(1) or not clearAndMove() then currentJob = "idle"; return false end end
    currentJob = "idle"
    return true
end

-- END MOVEMENT FUNCTIONS ----------------------------------------------------

function checkCancel()
    if cancelCurrentJob then
        print("Job canceled.")
        cancelCurrentJob = false -- Reset flag
        return true
    end
    return false
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
    
    cancelCurrentJob = false -- Reset cancel flag for new command

    local success
    if commandName == "cancel" then
        cancelCurrentJob = true
        currentJob = "idle"
        success = true
    elseif commandName == "home" then success = home()
    elseif commandName == "goto" then success = goto(table.unpack(args))
    elseif commandName == "setpos" then success = setpos(table.unpack(args))
    elseif commandName == "sethome" then success = sethome(table.unpack(args))
    elseif commandName == "forward" then currentJob = "moving forward"; success = move("forward")
    elseif commandName == "back" then currentJob = "moving back"; success = move("back")
    elseif commandName == "up" then currentJob = "moving up"; success = move("up")
    elseif commandName == "down" then currentJob = "moving down"; success = move("down")
    elseif commandName == "turnLeft" then currentJob = "turning left"; success = turn(turtle.turnLeft)
    elseif commandName == "turnRight" then currentJob = "turning right"; success = turn(turtle.turnRight)
    elseif commandName == "faceDirection" then currentJob = "facing direction"; success = faceDirection(table.unpack(args))
    elseif commandName == "scanChunk" then success = scanChunk()

    elseif commandName == "isInventoryFull" then
        local maxSlots = tonumber(args[1]) or 15
        if isInventoryFull(maxSlots) then print("Inventory is considered full.") else print("Inventory is not full.") end
        success = true
    elseif commandName == "transferToChest" then success = transferToChest()
    elseif commandName == "placeEnderChest" then success = placeEnderChest()

    elseif commandName == "enderUnloadInventory" then success = enderUnloadInventory(true)

    elseif turtle[commandName] and type(turtle[commandName]) == "function" then
        currentJob = "executing " .. commandName
        success = turtle[commandName]()
    else
        print("Unknown command: " .. cmd)
        success = false
    end
    
    if not cancelCurrentJob then
        currentJob = "idle"
    end
    reportStatus()
    return success
end

-- MAIN LOGIC -------------------------------------------------

function startSequence()
    print("Initializing...")

    if loadId() then
        print("Successfully loaded Turtle ID: " .. turtleId)
        shell.execute("label", "set", "Turtle "..turtleId)
    else
        print("No local ID found. Attempting to register with server...")
        while not registerWithServer() do
            print("Registration failed. Retrying in 5 seconds...")
            os.sleep(5)
        end
        print("Successfully registered. New Turtle ID: " .. turtleId)
    end

    if getGPSPos() then
        print("Position acquired via GPS.")
    elseif loadPosition() then
        print(string.format("Loaded position from file: X:%d, Y:%d, Z:%d, Dir:%d", position.x, position.y, position.z, position.dir))
    else
        print("No local position found. Syncing with server...")
        syncPositionWithServer()
    end

    sethome(position.x, position.y, position.z, position.dir)

    scanEnvironment()
    print("Ready. Reporting status to server.")
    reportStatus()
end

-- START THE TURTLE
startSequence()

while true do
    print("Polling...")
    local response = httpPost(serverHost .. "/poll/" .. turtleId, getStatus())

    if response and response.error == "re-register" then
        print("Server error: re-register. Deleting local ID file.")
        fs.delete(idFilePath)
        startSequence()
    end

    if response and response.commands and #response.commands > 0 then
        for _, cmd in ipairs(response.commands) do
            if not executeCommand(cmd) then
                if not cancelCurrentJob then
                    print("Command failed, aborting batch.")
                    reportStatus()
                    break
                end
            end
            os.sleep(0.2)
        end
    end
    os.sleep(pollInterval)
end