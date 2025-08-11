

from flask import Flask, request, jsonify, render_template_string, redirect, url_for
import numpy as np

app = Flask(__name__)

# --- Data Storage ---
turtles = {}
next_id = 1

# --- Constants ---
DIRECTIONS = {
    0: "North",
    1: "East",
    2: "South",
    3: "West"
}

# --- HTML Template ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Turtle C&C v2.5 - Home Command</title>
    <style>
        body { font-family: monospace; background-color: #1a1a1a; color: #f0f0f0; margin: 20px; }
        .container { display: flex; flex-wrap: wrap; gap: 20px; }
        .turtle-card { border: 1px solid #444; border-radius: 5px; padding: 15px; background-color: #2a2a2a; min-width: 350px; }
        .interface-section { background-color: #2a2a2a; border: 1px solid #444; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        h1, h2 { color: #00ff7f; }
        h3 { border-bottom: 1px solid #444; padding-bottom: 5px; }
        label { display: block; margin-top: 10px; color: #ccc; }
        input[type="text"], input[type="number"], input[type="submit"], select, button {
            font-size: 1em; padding: 8px; margin-top: 5px;
            background-color: #333; border: 1px solid #555; color: #f0f0f0; border-radius: 3px;
        }
        input[type="submit"], button { cursor: pointer; font-weight: bold; }
        input[type="submit"] { background-color: #008f4f; }
        input[type="submit"]:hover { background-color: #00ff7f; }
        .clear-btn { background-color: #ff4d4d; }
        .home-btn { background-color: #4d7cff; }
        .status-grid { display: grid; grid-template-columns: auto 1fr; gap: 5px 10px; }
        .status-grid dt { font-weight: bold; color: #00ff7f; }
        .command-queue { list-style-type: decimal; padding-left: 20px; max-height: 100px; overflow-y: auto; background: #111; padding: 10px; border-radius: 3px; }
        hr { border-color: #444; margin: 20px 0; }
        .button-group form { display: inline-block; margin-right: 10px; }
    </style>
</head>
<body>
    <h1>Turtle C&C Server v2.5</h1>
    <div class="interface-section">
        <h2>Control Panel</h2>
        <form method="post" action="/add_commands">
            <h3>Queue Commands</h3>
            <label for="turtle_id">Turtle ID:</label>
            <input type="text" id="turtle_id" name="turtle_id" required>
            <label for="commands">Commands (comma-separated):</label>
            <input type="text" id="commands" name="commands" placeholder="e.g., home, goto 5 10 15, sethome 0 0 0 0" required>
            <input type="submit" value="Queue Commands">
        </form>
    </div>
    <h2>Managed Turtles</h2>
    <div class="container">
    {% for id, data in turtles.items() %}
        <div class="turtle-card">
            <h3>Turtle #{{ id }}</h3>
            <dl class="status-grid">
                <dt>Location:</dt>  <dd>X:{{ data.status.get('x', '?') }}, Y:{{ data.status.get('y', '?') }}, Z:{{ data.status.get('z', '?') }}</dd>
                <dt>Direction:</dt> <dd>{{ DIRECTIONS.get(data.status.dir, 'Unknown') }} ({{ data.status.get('dir', '?') }})</dd>
                <dt>Fuel:</dt>      <dd>{{ data.status.get('fuel', 'N/A') }}</dd>
                <dt>Inventory:</dt> <dd>{{ data.status.get('inventory', {}) | tojson }}</dd>
            </dl>
            <h4>Command Queue:</h4>
            <ul class="command-queue">
            {% for cmd in data.queue %}
                <li>{{ cmd }}</li>
            {% else %}
                <li>Empty</li>
            {% endfor %}
            </ul>
            <div class="button-group" style="margin-top: 10px;">
                <!-- MODIFIED: "Send Home" button added -->
                <form method="post" action="/add_commands">
                    <input type="hidden" name="turtle_id" value="{{ id }}">
                    <input type="hidden" name="commands" value="home">
                    <button type="submit" class="home-btn">Send Home</button>
                </form>
                <form method="post" action="/clear_queue">
                    <input type="hidden" name="turtle_id" value="{{ id }}">
                    <button type="submit" class="clear-btn">Clear Queue</button>
                </form>
            </div>
        </div>
    {% endfor %}
    </div>
</body>
</html>
"""

def response_to_alone_turtle():
    return jsonify({"error": "re-register"}), 200

def render_main_page():
    return render_template_string(HTML_TEMPLATE, turtles=turtles, DIRECTIONS=DIRECTIONS)

@app.route('/')
def index():
    return render_main_page()

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
    print("Received scan data:")
    print(scan_data)

    # Extract block locations and convert to a NumPy array
    block_locations = []
    if 'blocks' in scan_data and isinstance(scan_data['blocks'], dict):
        for loc_str in scan_data['blocks'].keys():
            try:
                # Split the string 'x,y,z' into a list of strings ['x', 'y', 'z']
                # and convert each to an integer.
                coords = [int(coord) for coord in loc_str.split(',')]
                block_locations.append(coords)
            except ValueError:
                # Handle cases where a key is not in the expected format
                print(f"Could not parse location: {loc_str}")


    # Convert the list of locations to a NumPy array
    block_locations_np = np.array(block_locations)

    # You can now use this NumPy array for further processing or storage
    print("\nBlock locations as NumPy array:")
    print(block_locations_np)

    # Here you could save the array to a file, for example:
    # np.save(f'{turtle_id}_scan.npy', block_locations_np)

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

