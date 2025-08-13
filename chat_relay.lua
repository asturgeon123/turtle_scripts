--[[
Chat Box Monitor & Player Location Script for CC: Tweaked
Listens for chat messages to relay as commands AND listens for clicks on a
Player Detector to send the player their location via a toast notification.

NEW: If a command contains the word "here", it will be replaced with the
player's current X Y Z coordinates. Example: "goto here"

SETUP:
1. Place a computer next to a "Chat Box" and a "Player Detector".
2. Edit the three variables in the configuration section below.
3. Run this script.
]]

-- ========== CONFIGURATION ==========
-- The address of your Python Flask server.
local serverAddress = "http://192.168.1.71:5000" -- IMPORTANT: Change this!

-- The side the Chat Box peripheral is on (e.g., "top", "bottom", "left", "right", "front", "back")
local chatBoxSide = "left" -- IMPORTANT: Change this to the correct side!

-- The side the Player Detector peripheral is on
local playerDetectorSide = "right" -- IMPORTANT: Change this to the correct side!
-- ===================================

-- Attempt to wrap the peripherals
local chatBox = peripheral.wrap(chatBoxSide)
local playerDetector = peripheral.wrap(playerDetectorSide)

-- Validate that both peripherals were found
if not chatBox then
    printError("Chat Box not found on side: '" .. chatBoxSide .. "'")
    printError("Please check your setup and the config.")
    return
end

if not playerDetector then
    printError("Player Detector not found on side: '" .. playerDetectorSide .. "'")
    printError("Please check your setup and the config.")
    return
end

-- This function sends a command from the chat to the web server.
function relayCommand(command)
    local url = serverAddress .. "/chat_command"
    local payload = {
        command = command
    }
    local body = textutils.serializeJSON(payload)
    local headers = { ["Content-Type"] = "application/json" }

    print("Relaying command to server: '" .. command .. "'")
    
    -- Send the command to the server
    local response = http.post(url, body, headers)

    if response then
        local responseBody = response.readAll()
        local responseData = textutils.unserializeJSON(responseBody)
        
        if responseData and responseData.message then
             chatBox.sendMessage("Server: " .. responseData.message)
        else
            chatBox.sendMessage("Command sent to the server.")
        end
        response.close()
    else
        printError("Failed to send command to server.")
        chatBox.sendMessage("Error: Could not contact the command server.")
    end
end

-- This function gets the player's location and sends it as a toast.
function sendLocationToast(username)
    local pos = playerDetector.getPlayerPos(username)

    if pos then
        local locationString = string.format("X: %.0f, Y: %.0f, Z: %.0f", pos.x, pos.y, pos.z)
        chatBox.sendToastToPlayer(username, "Your Location", locationString)
        print("Sent location toast to " .. username .. ": " .. locationString)
    else
        printError("Could not get location for player: " .. username)
    end
end


-- ========== MAIN LOOP ==========
term.clear()
term.setCursorPos(1, 1)
print("Chat & Location Monitor ACTIVE")
print("Chat Box on side: " .. chatBoxSide)
print("Player Detector on side: " .. playerDetectorSide)
print("Listening for events...")

while true do
    -- Wait for any event to occur
    local eventData = {os.pullEvent()}
    local event = eventData[1]

    -- === Event Handler: Chat Message ===
    if event == "chat" then
        local username = eventData[2]
        local message = eventData[3]
        local processCommand = true -- Flag to control whether the command is sent

        print("Chat from " .. username .. ": " .. message)

        -- Check if the command contains the word "here", case-insensitively
        if message:find("[Hh][Ee][Rr][Ee]") then
            print("Keyword 'here' detected. Fetching coordinates for " .. username .. "...")
            local pos = playerDetector.getPlayerPos(username)


            if pos then
                -- If coordinates are found, format them and replace "here"
                local coords = string.format("%.0f %.0f %.0f", pos.x, pos.y, pos.z)
                -- Replace all occurrences of "here", "Here", "HERE", etc. with the coordinates
                message = message:gsub("[Hh][Ee][Rr][Ee]", coords)
                print("Command modified to: '" .. message .. "'")
            else
                -- If coordinates can't be found, print an error and notify the player
                printError("Could not get location for player: " .. username)
                chatBox.sendMessageToPlayer(username, "Error: Could not get your location to use 'here'.")
                -- Mark the command to not be processed
                processCommand = false
            end
        end

        -- Relay the command if it's valid and should be processed
        if processCommand and message and message:gsub("%s*", "") ~= "" then
            relayCommand(message)
        elseif not processCommand then
            print("Command ignored due to a processing error.")
        else
            print("Message ignored (empty).")
        end

    -- === Event Handler: Player Clicks Detector ===
    elseif event == "playerClick" then
        local username = eventData[2]
        local clickedSide = eventData[3]
        
        -- Check if the clicked peripheral was the player detector
        if clickedSide == playerDetectorSide then
            print(username .. " clicked the detector.")
            sendLocationToast(username)
        end
    end
end