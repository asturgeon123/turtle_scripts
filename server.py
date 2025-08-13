from flask import Flask, request, jsonify, render_template, redirect, url_for
import numpy as np
import math
from pathfinding3d.core.diagonal_movement import DiagonalMovement
from pathfinding3d.core.grid import Grid
from pathfinding3d.finder.a_star import AStarFinder

app = Flask(__name__)

# --- Data Storage ---
turtles = {}
next_id = 1

# Using a NumPy array for world block coordinates for memory efficiency.
world_blocks = np.empty((0, 3), dtype=int)
# Storing non-numerical block data (name, color) in a separate dictionary,
# keyed by a coordinate string for easy lookup.
block_info = {}

# --- Constants ---
DIRECTIONS = {
    0: "North",
    1: "East",
    2: "South",
    3: "West"
}

def get_best_turtle():
    """
    Finds the best turtle to receive a new command.

    The selection process works as follows:
    1. It first searches for any "idle" turtles, which are defined as turtles
       with an empty command queue. If multiple idle turtles exist, it returns
       the first one it finds.
    2. If no idle turtles are available, it then finds the turtle with the
       shortest command queue (the least busy turtle).
    3. If there are no registered turtles at all, it returns None.

    Returns:
        str: The ID of the selected turtle, or None if no turtles are available.
    """
    # Return None immediately if there are no turtles registered.
    if not turtles:
        return None

    # First priority: Find any turtle that is completely idle.
    # An idle turtle is one with an empty command queue.
    for turtle_id, turtle_data in turtles.items():
        if not turtle_data['queue']:
            print(f"Found idle turtle: {turtle_id}")
            return turtle_id

    # If no idle turtles were found, find the one with the shortest queue.
    # This is achieved by using the min() function on the turtle IDs,
    # with a key that specifies we should compare them based on the length
    # of their command queue.
    best_turtle = min(turtles, key=lambda tid: len(turtles[tid]['queue']))
    print(f"No idle turtles. Found turtle with shortest queue: {best_turtle}")
    
    return best_turtle

def get_block_properties(block_name):
    """Returns the color and pathfinding cost for a given block name."""
    if 'grass' in block_name:
        return "#55a630", 5  # Cost to dig
    elif 'ore' in block_name:
        return "#37eb34", 10 # Higher cost for valuable ores
    elif 'dirt' in block_name:
        return "#967969", 5
    elif 'stone' in block_name:
        return "#808080", 8
    elif 'lava' in block_name:
        return "#eb3434", 0  # Impassable (cost 0 in pathfinding3d library)
    else:
        return "#808080", 1  # Default to air/walkable

def translate_path_to_waypoint_commands(path):
    """
    Converts a path into an optimized list of goto() commands, only issuing
    a command when the direction of travel changes.
    """
    if len(path) < 2:
        return []

    waypoints = []
    # Calculate the initial direction vector.
    last_direction = (
        path[1][0] - path[0][0],
        path[1][1] - path[0][1],
        path[1][2] - path[0][2],
    )

    # Iterate from the third point to the end.
    for i in range(2, len(path)):
        # Calculate the vector from the previous point to the current one.
        current_direction = (
            path[i][0] - path[i-1][0],
            path[i][1] - path[i-1][1],
            path[i][2] - path[i-1][2],
        )
        
        # If the direction changes, the previous point was a "corner".
        if current_direction != last_direction:
            waypoints.append(path[i-1])
            last_direction = current_direction

    # The final destination is always the last waypoint.
    waypoints.append(path[-1])

    # Format the waypoints into goto commands.
    commands = [f"goto {p[0]} {p[1]} {p[2]}" for p in waypoints]
    return commands

def get_chunk_center(x, y, z):
  """
  Calculates the center coordinates of a Minecraft chunk from a given position.

  A Minecraft chunk is a 16x16 block area on the X and Z axes. This function
  first determines the chunk that the given coordinates belong to. It then
  calculates the coordinates of the north-west block of the 2x2 central area
  of that chunk. The input y-coordinate is returned as is, as chunks extend
  through the entire world height.

  Args:
    x: The player's current x-coordinate.
    y: The player's current y-coordinate.
    z: The player's current z-coordinate.

  Returns:
    A tuple containing the (x, y, z) coordinates of the center of the chunk.
  """
  chunk_x = math.floor(x / 16)
  chunk_z = math.floor(z / 16)
  
  # The chunk's origin corner (most north-west)
  chunk_start_x = chunk_x * 16
  chunk_start_z = chunk_z * 16
  
  # The center of a 16 block wide area is between block 7 and 8.
  # We will return the coordinates of the block at offset 7.
  center_x = chunk_start_x + 7
  center_z = chunk_start_z + 7
  
  return (center_x, y, center_z)

def response_to_alone_turtle():
    return jsonify({"error": "re-register"}), 200



def path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z):
    global world_blocks
    
    # Determine grid boundaries
    min_x = min(start_x, dest_x) - 5
    max_x = max(start_x, dest_x) + 5
    min_y = min(start_y, dest_y) - 5
    max_y = max(start_y, dest_y) + 5
    min_z = min(start_z, dest_z) - 5
    max_z = max(start_z, dest_z) + 5

    # Create cost matrix
    grid_matrix = np.ones((max_x - min_x + 1, max_y - min_y + 1, max_z - min_z + 1), dtype=np.uint8)
    
    # Populate with known block costs
    for coords in world_blocks:
        x, y, z = coords
        if min_x <= x <= max_x and min_y <= y <= max_y and min_z <= z <= max_z:
            block_key = f"{x},{y},{z}"
            name = block_info.get(block_key, {}).get('name', 'unknown')
            
            _, cost = get_block_properties(name)
            
            grid_matrix[x - min_x, y - min_y, z - min_z] = cost

    grid = Grid(matrix=grid_matrix)
    start_node = grid.node(start_x - min_x, start_y - min_y, start_z - min_z)
    end_node = grid.node(dest_x - min_x, dest_y - min_y, dest_z - min_z)

    finder = AStarFinder()
    path, _ = finder.find_path(start_node, end_node, grid)

    if path:
        # Translate grid path back to world coordinates
        world_path = [(p.x + min_x, p.y + min_y, p.z + min_z) for p in path]
        
        # Use the new, simpler translation function to generate goto() commands
        commands = translate_path_to_waypoint_commands(world_path)
        
        turtles[turtle_id]['queue'].extend(commands)
        print(f"Path for turtle {turtle_id}: {commands}")


@app.route('/find_and_mine/<turtle_id>/<block_name>', methods=['POST'])
def find_and_mine(turtle_id, block_name):
    if turtle_id not in turtles:
        return "Turtle not found", 404

    status = turtles[turtle_id]['status']
    start_x, start_y, start_z = status['x'], status['y'], status['z']

    # Find all blocks of the specified type
    target_blocks = []
    for coords in world_blocks:
        block_key = f"{coords[0]},{coords[1]},{coords[2]}"
        if block_info.get(block_key, {}).get('name') == block_name:
            target_blocks.append(coords)

    if not target_blocks:
        return "No blocks of that type found", 404

    # Find the nearest block
    nearest_block = min(target_blocks, key=lambda p: math.sqrt((p[0] - start_x)**2 + (p[1] - start_y)**2 + (p[2] - start_z)**2))
    dest_x, dest_y, dest_z = nearest_block

    # Pathfind to the nearest block
    path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)
    
    # Add a command to mine the block
    turtles[turtle_id]['queue'].append(f"mine {dest_x} {dest_y} {dest_z}")

    return redirect(url_for('index'))


def find_and_mine_all(turtle_id, block_name):
    """
    Finds all blocks of a specified type and queues commands for a turtle
    to navigate to and mine each one sequentially.
    """
    if turtle_id not in turtles:
        return "Turtle not found", 404

    status = turtles[turtle_id]['status']
    current_x, current_y, current_z = status['x'], status['y'], status['z']

    # Find all blocks of the specified type
    target_blocks = []
    for coords in world_blocks:
        block_key = f"{coords[0]},{coords[1]},{coords[2]}"
        if block_info.get(block_key, {}).get('name') == block_name:
            target_blocks.append(coords)

    if not target_blocks:
        return jsonify({"status": "error", "message": f"Sorry, I can't find any {block_name}."})

    # Sort the blocks by distance from the turtle's starting position for a more efficient path
    target_blocks.sort(key=lambda p: math.sqrt((p[0] - current_x)**2 + (p[1] - current_y)**2 + (p[2] - current_z)**2))

    # Iterate through all target blocks, pathfind, and queue a mine command for each. [4]
    for block_coords in target_blocks:
        dest_x, dest_y, dest_z = block_coords

        # Pathfind from the turtle's last known position to the next block
        path_to_block(turtle_id, current_x, current_y, current_z, dest_x, dest_y, dest_z)
        
        # Add a command to mine the block at the destination
        turtles[turtle_id]['queue'].append(f"goto {dest_x} {dest_y} {dest_z}")

        # Update the current position to the location of the block just mined
        # This ensures the next pathfinding operation starts from the correct location
        current_x, current_y, current_z = dest_x, dest_y, dest_z

    return jsonify({"status": "ok", "message": f"Task assigned to turtle {turtle_id}: mine {block_name}"})

@app.route('/pathfind/<turtle_id>/<x>/<y>/<z>', methods=['GET'])
def pathfind(turtle_id,x,y,z):
    if turtle_id not in turtles:
        return "Turtle not found", 404
    
    try:
        dest_x = int(x)
        dest_y = int(y)
        dest_z = int(z)
    except ValueError:
        return "Invalid coordinates", 400

    status = turtles[turtle_id]['status']
    start_x, start_y, start_z = status['x'], status['y'], status['z']
    
    path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)

    return redirect(url_for('index'))

@app.route('/')
def index():
    return render_template('index.html', turtles=turtles, DIRECTIONS=DIRECTIONS)

@app.route('/world')
def world_view():
    return render_template('world.html')

@app.route('/world_data')
def world_data():
    """
    Prepares world data for JSON serialization.
    - Turtles are read directly from the dictionary.
    - Blocks are constructed by combining the NumPy coordinates with the metadata dict.
    """
    blocks_list = []
    # Iterate through each coordinate row in the NumPy array
    for coords in world_blocks:
        # Create the same key used for storing to look up metadata
        block_key = f"{coords[0]},{coords[1]},{coords[2]}"
        info = block_info.get(block_key, {"name": "unknown", "color": "#808080"})

        # Append a JSON-friendly dictionary to the list.
        # It's important to cast NumPy integers to standard Python ints.
        blocks_list.append({
            "x": int(coords[0]),
            "y": int(coords[1]),
            "z": int(coords[2]),
            "name": info['name'],
            "color": info['color']
        })

    # Return the data in the format the frontend expects
    return jsonify({"turtles": turtles, "blocks": blocks_list})

@app.route('/register', methods=['POST'])
def register_turtle():
    global next_id
    turtle_id = str(next_id)
    initial_status = request.json or {"x": 0, "y": 0, "z": 0, "dir": 0, "fuel": "N/A", "inventory": {}}
    turtles[turtle_id] = { "status": initial_status, "queue": [] }
    print(f"Registered new turtle with ID: {turtle_id}")
    next_id += 1
    return jsonify({"id": turtle_id})

@app.route('/get_position/<turtle_id>', methods=['GET'])
def get_position(turtle_id):
    if turtle_id in turtles:
        status = turtles[turtle_id].get("status", {})
        pos_data = { "x": status.get("x"), "y": status.get("y"), "z": status.get("z"), "dir": status.get("dir") }
        return jsonify(pos_data)
    return jsonify({"error": "Turtle not found"}), 404

@app.route('/poll/<turtle_id>', methods=['POST'])
def poll_for_command(turtle_id):
    if turtle_id not in turtles:
        return response_to_alone_turtle()
    turtles[turtle_id]["status"] = request.json
    commands_to_send = turtles[turtle_id]["queue"][:]
    turtles[turtle_id]["queue"] = []
    return jsonify({"commands": commands_to_send})

@app.route('/scan_report/<turtle_id>', methods=['POST'])
def scan_report(turtle_id):
    """
    Processes incoming block data and stores it efficiently.
    - Coordinates are added to the NumPy array.
    - Metadata is stored in the block_info dictionary.
    """
    global world_blocks # Declare that we are modifying the global variable

    if turtle_id not in turtles:
        return response_to_alone_turtle()

    scan_data = request.json

    if 'blocks' in scan_data and isinstance(scan_data['blocks'], dict):
        new_coords_list = []
        for loc_str, block_name in scan_data['blocks'].items():
            try:
                # Parse coordinates from the string key
                coords = [int(coord) for coord in loc_str.split(',')]
                new_coords_list.append(coords)

                # Store the metadata (name, color) in the dictionary using the string as a key
                block_key = f"{coords[0]},{coords[1]},{coords[2]}"
                color, _ = get_block_properties(block_name)
                block_info[block_key] = {"name": block_name, "color": color}

            except ValueError:
                print(f"Could not parse location: {loc_str}")

        # If any new blocks were successfully parsed, add them to the main array
        if new_coords_list:
            # Convert the list of new coordinates to a NumPy array
            new_blocks_arr = np.array(new_coords_list, dtype=int)
            # Vertically stack the old and new arrays
            combined_blocks = np.vstack([world_blocks, new_blocks_arr])
            # Use np.unique to remove any duplicate coordinates efficiently
            world_blocks = np.unique(combined_blocks, axis=0)

    return jsonify({"status": "ok", "message": "Scan data processed."})

@app.route('/update/<turtle_id>', methods=['POST'])
def update_status(turtle_id):
    if turtle_id not in turtles:
        return response_to_alone_turtle()
    turtles[turtle_id]["status"] = request.json
    return jsonify({"status": "ok"})

@app.route('/chat_command', methods=['POST'])
def chat_command():
    # Automatically select the best turtle.
    turtle_id = get_best_turtle()

    # Handle case where no turtles are available.
    if not turtle_id:
        return jsonify({"status": "error", "message": "No turtles are currently available."}), 503

    data = request.json
    command_str = data.get('command')
    
    print(data)

    if command_str:
        parts = command_str.split()
        cmd_type = parts[0].lower()
        
        print(cmd_type)
        print(parts)

        if cmd_type == "mine" and len(parts) > 1:
            block_name = parts[1]
            status = turtles[turtle_id]['status']
            start_x, start_y, start_z = status['x'], status['y'], status['z']

            target_blocks = [coords for coords in world_blocks if block_info.get(f"{coords[0]},{coords[1]},{coords[2]}", {}).get('name') == block_name]

            if target_blocks:
                nearest_block = min(target_blocks, key=lambda p: math.sqrt((p[0] - start_x)**2 + (p[1] - start_y)**2 + (p[2] - start_z)**2))
                dest_x, dest_y, dest_z = nearest_block
                path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)
                turtles[turtle_id]['queue'].append(f"mine {dest_x} {dest_y} {dest_z}")
                turtles[turtle_id]['queue'].append(f"say Task received: mining {block_name}")
                return jsonify({"status": "ok", "message": f"Task assigned to turtle {turtle_id}: mine {block_name}"})
            else:
                # No need to queue a 'say' command if the server can respond directly.
                return jsonify({"status": "error", "message": f"Sorry, I can't find any {block_name}."})
            
        elif cmd_type == "mineall" and len(parts) > 1:
            print("WE ARE MINING ALLLLLLL")
            block_name = parts[1]

            status = turtles[turtle_id]['status']
            start_x, start_y, start_z = status['x'], status['y'], status['z']

            return find_and_mine_all(turtle_id, block_name)

        elif cmd_type == "goto" and len(parts) == 4:
            try:
                
                
                status = turtles[turtle_id]['status']
                start_x, start_y, start_z = status['x'], status['y'], status['z']
                dest_x, dest_y, dest_z = map(int, parts[1:])
                path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)
                
                return jsonify({"status": "ok", "message": f"Turtle {turtle_id} is now moving to ({dest_x}, {dest_y}, {dest_z})."})
            except ValueError:
                return jsonify({"status": "error", "message": "Invalid coordinates for 'goto' command."})
        else:
            # For other simple commands like "dig", "forward", etc.
            turtles[turtle_id]['queue'].append(command_str)
            return jsonify({"status": "ok", "message": f"Command '{command_str}' queued for turtle {turtle_id}."})

    return jsonify({"status": "error", "message": "Invalid or empty command."}), 400

@app.route('/add_commands', methods=['POST'])
def add_commands():
    
    turtle_id = request.form.get('turtle_id')
    commands_str = request.form.get('commands', '')
    
    if turtle_id in turtles and commands_str:
        # Split commands by comma or newline for flexibility
        commands_list = [cmd.strip() for cmd in commands_str.replace(',', '\n').split('\n') if cmd.strip()]
        
        for command in commands_list:
            parts = command.split()
            cmd_type = parts[0].lower()

            if cmd_type == "mine" and len(parts) > 1:
                block_name = parts[1]
                
                # Trigger the find_and_mine logic
                status = turtles[turtle_id]['status']
                start_x, start_y, start_z = status['x'], status['y'], status['z']

                # Find all blocks of the specified type
                target_blocks = []
                for coords in world_blocks:
                    block_key = f"{coords[0]},{coords[1]},{coords[2]}"
                    if block_info.get(block_key, {}).get('name') == block_name:
                        target_blocks.append(coords)

                if target_blocks:
                    # Find the nearest block
                    nearest_block = min(target_blocks, key=lambda p: math.sqrt((p[0] - start_x)**2 + (p[1] - start_y)**2 + (p[2] - start_z)**2))
                    dest_x, dest_y, dest_z = nearest_block

                    # Pathfind to the nearest block
                    path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)
                    
                    # Add a command to mine the block
                    turtles[turtle_id]['queue'].append(f"mine {dest_x} {dest_y} {dest_z}")
                else:
                    print(f"No blocks of type {block_name} found for turtle {turtle_id}")

            elif cmd_type == "goto" and len(parts) == 4:
                # Handle direct goto commands as before
                status = turtles[turtle_id]['status']
                start_x, start_y, start_z = status['x'], status['y'], status['z']
                dest_x, dest_y, dest_z = map(int, parts[1:])
                path_to_block(turtle_id, start_x, start_y, start_z, dest_x, dest_y, dest_z)
            else:
                # Handle other simple commands
                turtles[turtle_id]['queue'].append(command)
                
        print(f"Added commands to turtle {turtle_id}: {commands_list}")
        
    return redirect(url_for('index'))

@app.route('/clear_queue', methods=['POST'])
def clear_queue():
    turtle_id = request.form.get('turtle_id')
    if turtle_id in turtles:
        turtles[turtle_id]['queue'] = []
    return redirect(url_for('index'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)