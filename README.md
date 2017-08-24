# CreepBlockAI
The challenge of creating a bot for Dota 2 is the vast amount of information available at every frame, and the continuous set of actions possible. 

Click on the picture below to view the video of the trained AI
[![CreepBlockAI](https://img.youtube.com/vi/u04HQP2hICU/0.jpg)](https://www.youtube.com/watch?v=u04HQP2hICU)

# About
I am currently investigating what sort of model can effectively tackle the problem above. My code here is one iteration of my tinkering where I input the (x,y) offset of the creeps relative to the hero as state, and the output are 2D normal distributions from which I sample the (x,y) offset my hero should move. Actions are performed every 0.2 seconds.

I constrain myself to a creepblock scenario as it is a simple enough test for whether or not my model is effective. The objective is to block the creeps as much as possible. Every 5 episodes, I use a hardcoded bot to "bootstrap" the training in an effort to get the model to learn faster.

# The Model and Training
My model consists of an online policy network, and target policy network. 

The dota 2 addon (i.e. the bot in the game) runs the target policy network which outputs 60 values (20 x 3 parameters). The 3 parameters are mean1, mean2 of a 2D normal distribution with fixed variance of 5 and correlation of 0. The last parameter is the weight. The maximal weighted distribution is chosen, and an action is sampled from that distribution.

The tensorflow component consists of the online policy network. The loss is the loglikelihood of a certain action. I directly use the reward to perform gradient ascent/descent. i.e. if the reward is positive, the backpropagation will increase the loglikelihood, and the opposite if the reward is negative. 

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


# Pre-trained Model
I have provided my pre-trained model in 2 forms:
1. as the actual python weights which can be loaded via the tensorflow webservice
2. hardcoded into the creep_block_ai_pretrained lua files. Running this addon just runs the trained model without any additional learning
