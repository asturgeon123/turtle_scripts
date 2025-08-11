from flask import Flask, request, jsonify, render_template, redirect, url_for
import numpy as np

app = Flask(__name__)

# --- Data Storage ---
turtles = {}
world_blocks = {} # New: To store scanned blocks
next_id = 1

# --- Constants ---
DIRECTIONS = {
    0: "North",
    1: "East",
    2: "South",
    3: "West"
}

def get_color_for_block(block_name):
    if 'grass' in block_name:
        return "#55a630"
    elif 'ore' in block_name:
        return "#b8860b"
    elif 'dirt' in block_name:
        return "#967969"
    else:
        return "#808080"
        
    
        


def response_to_alone_turtle():
    return jsonify({"error": "re-register"}), 200

@app.route('/')
def index():
    return render_template('index.html', turtles=turtles, DIRECTIONS=DIRECTIONS)

# New: Route for the 3D world view
@app.route('/world')
def world_view():
    return render_template('world.html')

# New: Endpoint to get world data
@app.route('/world_data')
def world_data():
    return jsonify({"turtles": turtles, "blocks": world_blocks})

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
    if turtle_id not in turtles:
        return response_to_alone_turtle()

    scan_data = request.json
    print(scan_data)

    if 'blocks' in scan_data and isinstance(scan_data['blocks'], dict):
        for loc_str, block_name in scan_data['blocks'].items(): # Renamed 'block_info' to 'block_name' for clarity
            try:
                coords = [int(coord) for coord in loc_str.split(',')]
                block_key = f"{coords[0]},{coords[1]},{coords[2]}"

                # --- CORRECTED LINE ---
                world_blocks[block_key] = {"x": coords[0], "y": coords[1], "z": coords[2], "name": block_name, "color": get_color_for_block(block_name)}

            except ValueError:
                print(f"Could not parse location: {loc_str}")

    return jsonify({"status": "ok", "message": "Scan data processed."})


@app.route('/update/<turtle_id>', methods=['POST'])
def update_status(turtle_id):
    if turtle_id not in turtles:
        return response_to_alone_turtle()
    turtles[turtle_id]["status"] = request.json
    return jsonify({"status": "ok"})

@app.route('/add_commands', methods=['POST'])
def add_commands():
    turtle_id = request.form.get('turtle_id')
    commands_str = request.form.get('commands', '')
    if turtle_id in turtles and commands_str:
        commands_list = [cmd.strip() for cmd in commands_str.split(',') if cmd.strip()]
        turtles[turtle_id]['queue'].extend(commands_list)
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