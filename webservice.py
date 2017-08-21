from flask import Flask, jsonify, request
from ActorCritic import Model

app = Flask(__name__)

m = Model()

@app.route('/CreepBlockAI/model', methods=['GET'])
def get_model():
    return jsonify(m.get_update())

@app.route('/CreepBlockAI/update', methods=['POST'])
def update():
    m.run(request.json)
    return jsonify({})

@app.route('/CreepBlockAI/dump', methods=['GET'])
def dump():
    m.dump()
    return jsonify({})
    
@app.route('/CreepBlockAI/load', methods=['POST'])
def load():
    m.load(request.json['file'])
    return jsonify({})
    
if __name__ == '__main__':  
    app.run()