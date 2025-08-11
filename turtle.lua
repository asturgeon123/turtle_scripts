-- scanner.lua

---
-- Connects to the Geo Scanner peripheral.
-- @return The wrapped peripheral object, or nil if not found.
---
local function connectToScanner()
  -- Try to find a peripheral of the type "geoScanner" attached to any side.
  local scanner = peripheral.find("geo_scanner")
  if scanner == nil then
    print("Error: Geo Scanner not found.")
    print("Please place a Geo Scanner next to this computer.")
  end
  return scanner
end

---
-- Scans the area and organizes the results into a dictionary (table)
-- where keys are block names.
-- @param scanner The connected geoscanner peripheral.
-- @param radius The radius to scan.
-- @return A dictionary-like table of scan results, or nil if scan failed.
---
local function scanAndCreateDictionary(scanner, radius)
  print("Scanning radius of " .. radius .. " blocks...")

  -- Perform the scan. It returns a list of blocks or nil + error message.
  local blocksFound, reason = scanner.scan(radius)

  -- Check if the scan was successful
  if not blocksFound then
    print("Scan failed: " .. reason)
    return nil
  end

  print("Scan complete. Found " .. #blocksFound .. " blocks.")
  print("Organizing results into a dictionary...")

  -- This is our main dictionary (table) to store the organized results.
  local blockDictionary = {}

  -- Loop through every block returned by the scan
  for i, blockData in ipairs(blocksFound) do
    local name = blockData.name -- Get the name of the current block

    -- If this block name is not yet a key in our dictionary...
    if blockDictionary[name] == nil then
      -- ...create a new empty list for it.
      blockDictionary[name] = {}
    end

    -- Add the current block's data to the list for its name.
    table.insert(blockDictionary[name], blockData)
  end

  print("Dictionary created successfully.")
  return blockDictionary
end

---
-- Main execution part of the program
---
local geoscanner = connectToScanner()

-- Only proceed if the scanner was found
if geoscanner then
  -- Define the radius for our scan
  local scanRadius = 100

  -- Call our function to get the dictionary
  local resultDictionary = scanAndCreateDictionary(geoscanner, scanRadius)

  -- If the dictionary was created successfully, print the results
  if resultDictionary then
    print("\n--- Scan Results by Block Type ---")
    -- Iterate through the dictionary and print what we found
    for blockName, blockList in pairs(resultDictionary) do
      -- #blockList gets the count of items in the list
      print(blockName .. ": Found " .. #blockList)
    end
  end
end