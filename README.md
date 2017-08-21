# CreepBlockAI
The challenge of creating a bot for Dota 2 is the vast amount of information available at every frame, and the continuous set of actions possible. 

Click on the picture below to view the video of the AI in training.
[![CreepBlockAI](https://img.youtube.com/vi/UVE0rxcffYo/0.jpg)](https://www.youtube.com/watch?v=UVE0rxcffYo)

# About
I am currently investigating what sort of model can effectively tackle the problem above. My code here is one iteration of my tinkering where I discretize actions into 8 directions + 1 hold, and I use the (x,y) offset of the creeps relative to the hero as input/state. Actions are performed every 0.2 seconds.

I constrain myself to a creepblock scenario as it is a simple enough test for whether or not my model is effective. The objective is to block the creeps as much as possible. Every 5 episodes, I use a hardcoded bot to "bootstrap" the training in an effort to get the model to learn faster.

# The Model and Training
My model consists of an online policy network, online value network, and target policy network. 

The dota 2 addon (i.e. the bot in the game) runs the target policy network which outputs the probability of selecting an action. Actions are sampled from the output. The role of this is to gather experience which is then passed to a webservice integrated with tensorflow.

The tensorflow component consists of the online policy network and online value network. The experience is used to train these 2 networks. 

Every 10 episodes, the online target network is replaced with the online policy network.

# How to install
1. Install Dota Workshop Tools
2. Create an empty addon
3. Copy `addon_game_mode.lua` into the appropiate addon folder (overwrite the file)
4. Launch Dota Workshop Tools with your created addon
5. Open vConsole and execute 
`dota_launch_custom_game <name of your addon> dota`
6. Run the webservice
`python webservice.py`

# Speed up learning
Use `host_timescale xx` in Dota 2 Console to speed up the game where xx is the scaling factor.

Note that speeding up too much means the bot cannot compute an action in time. I find that I can comfortable run simulations at 2x speed.
