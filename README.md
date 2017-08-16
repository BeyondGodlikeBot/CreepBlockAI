# CreepBlockAI
Creep Block Test Scenario for Episodic Reinforcement Learning 

# How to install
1. Install Dota Workshop Tools
2. Create an empty addon
3. Copy `addon_game_mode.lua` into the appropiate addon folder (overwrite the file)
4. Launch Dota Workshop Tools with your created addon
5. Open vConsole and execute 
`dota_launch_custom_game <name of your addon> dota`

# How to use
Create a machine learning algorithm integrated with a webservice which listens to "http://localhost:5000/CreepBlockAI". A python example `webservice.py` is provided

The Test Scenario (Custom Map) will call that webservice automatically with POST requests

If POST data is empty, the Test Scenario is in waiting mode. 
Respond with encoded JSON `{ 'command' : 'STARTSCENARIO' }` to spawn a wave of creeps

If POST data is not empty, the Test Scenario is running.
Respond with encoded JSON `{ 'command' : XXX }` to control Shadow Fiend where XXX can be:
* 1 of 16 Directional Commands (N, NNE, NE, NEE, E, SEE, SE, SSE, S, SSW, SW, SWW, W, NWW, NW, NNW); or
* STOP

When the Test Scenario is running, the following data will be in the POST request:
* Hero, Creep1, Creep2, Creep3, Creep4 - [x,y,z] Position Data 
* Step - Integer from 1 to 80

Note step 80 is the terminal state which is ~16s in game time. Roughly the amount of time for an unblocked creep wave to reach the middle

All of this can be edited in `addon_game_mode.lua`

# Speed up learning
Use `host_timescale xx` in Dota 2 Console to speed up the game where xx is the scaling factor. On my machine, I am able to run at 5-10x speed stably even when calling a Tensorflow model.
