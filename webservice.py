from flask import Flask, jsonify, request
import sys
import numpy as np

global moves
moves = ['N','NNE','NE','NEE',
         'E','SEE','SE','SSE',
         'S','SSW','SW','SWW',
         'W','NWW','NW','NNW',
         'STOP']
app = Flask(__name__)
    

@app.route('/MidOnlyAI/service', methods=['POST'])
def get_scenario_command():
    global moves
    if request.json is None:
        cmd = 'START'
        print("Step: None, Cmd: %s" % cmd, file=sys.stderr)
    else:
        cmd = moves[np.random.randint(0,len(moves))]
        print("Step: %d, Cmd: %s" % (request.json['step'], cmd), file=sys.stderr)
    return jsonify({'command': cmd})

if __name__ == '__main__':    
    app.run()