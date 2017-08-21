import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
import tensorflow as tf
import numpy as np
import sys
import json

class Model:
    def __init__(self):
        self.ep = 0
        self.boot_strap = 100
        self.boost_strap_freq = 5
        self.target_replace_freq = 10
        self.save_freq = 25        
        
        self.memory = Memory()
        self.policy_net = Net(POLICY_NET)
        self.value_net = Net(VALUE_NET)
        
        self.sess = tf.InteractiveSession()
        self.sess.run(tf.global_variables_initializer())
        
    def get_update(self):
        data = self.policy_net.get_weights(self.sess)
        data['boot_strap'] = self.boot_strap
        data['replace'] = self.ep % self.target_replace_freq == 0
        return data
        
    def dump(self):
        data = { 'value_net' : self.value_net.get_weights(self.sess),
                 'policy_net' : self.policy_net.get_weights(self.sess) }
        np.save('dump%d.npy' % self.ep,data)               
        
    def load(self, file):
        print("Loading: " + file, file=sys.stderr)
        data = np.load(file).item()   
        self.value_net.set_weights( data['value_net'], self.sess )
        self.policy_net.set_weights( data['policy_net'], self.sess )
        print("Sucess", file=sys.stderr)    
                        
    def run(self,data):
        with open('asd.txt','w') as f:
            f.write(json.dumps(data))
        if data['ep'] == self.ep:
            print("Duplicate ep %d" % self.ep, file=sys.stderr)
            return            
        self.ep = data['ep']
        print("Ep: %d" % self.ep, file=sys.stderr)
        
        for d in self.parse_data(data):
            self.memory.insert(d)
            
            if self.memory.full() and np.random.rand() < 0.1:
                batch = self.memory.get_batch()
                s_t, action, reward = zip(*batch)
                
                s_t = np.array(s_t, dtype=np.float32)
                action = np.array(action, dtype=np.int32)
                reward = np.array(reward, dtype=np.float32)
                
                _, value_loss, td_error = self.sess.run([self.value_net.optim, 
                                                   self.value_net.loss, 
                                                   self.value_net.delta],
                                                   feed_dict={self.value_net.target : reward,
                                                              self.value_net.s_t : s_t })
                _, policy_loss = self.sess.run([self.policy_net.optim,
                                                self.policy_net.loss],
                                                feed_dict={self.policy_net.target : td_error,
                                                           self.policy_net.s_t : s_t,
                                                           self.policy_net.action : action})
                
                print("VLoss: %0.3f, PLoss: %0.3f" % (value_loss, policy_loss), file=sys.stderr)
                
                self.memory.update_batch_td_error(td_error)
        
        if not self.memory.full():
            print("Experience %d of %d gathered" % (self.memory.curr_idx, self.memory.mem_size), file=sys.stderr)

        if self.ep % self.boost_strap_freq == 0:
            self.boot_strap = 100
        else:
            self.boot_strap = 0         
                          
        if self.ep % self.save_freq == 0:
            print("Saving weights", file=sys.stderr)
            self.dump()
        
    def parse_data(self,data):
        s_t = []
        action = []
        reward = []
        
        R = 0
        for i in reversed(range(len(data) - 1)):
            d_t = data[str(i)]
            
            R = d_t['r'] + 0.9*R
            s_t.append(d_t['s'])
            action.append(d_t['a'])
            reward.append(R)
        
        s_t = np.array(s_t, dtype=np.float32)
        action = np.array(action, dtype=np.int32) - 1
        reward = np.array(reward, dtype=np.float32)
        
        reward = np.clip(reward, -2, 2)
        
        return zip(s_t, action, reward)
           
VALUE_NET = 0
POLICY_NET = 1
class Net:
    def __init__(self, net_type):
        self.s_t = tf.placeholder(dtype=tf.float32, shape=[None, 8])
        self.var = {}
        scope = "value" if net_type == VALUE_NET else "policy"
        with tf.variable_scope(scope):
            self.var['W1'] = tf.get_variable('W1',shape=[2,50], initializer=tf.contrib.layers.xavier_initializer())
            self.var['b1'] = tf.Variable(tf.zeros([50]), dtype=tf.float32)
            self.var['W2'] = tf.get_variable('W2',shape=[50,50], initializer=tf.contrib.layers.xavier_initializer())
            self.var['b2'] = tf.Variable(tf.zeros([50]), dtype=tf.float32)
            self.var['W3'] = tf.get_variable('W3',shape=[25,25], initializer=tf.contrib.layers.xavier_initializer())
            self.var['b3'] = tf.Variable(tf.zeros([25]), dtype=tf.float32)
            if net_type == VALUE_NET:
                self.var['W4'] = tf.get_variable('W4',shape=[25,1], initializer=tf.contrib.layers.xavier_initializer())
                self.var['b4'] = tf.Variable(tf.zeros([1]), dtype=tf.float32)
            else: #policy net
                self.var['W4'] = tf.get_variable('W4',shape=[25,9], initializer=tf.contrib.layers.xavier_initializer())
                self.var['b4'] = tf.Variable(tf.zeros([9]), dtype=tf.float32)
            
        
        creeps = tf.split(self.s_t, num_or_size_splits=4, axis=1)
        self.fc1 = [tf.nn.tanh(tf.matmul(c, self.var['W1']) + self.var['b1']) for c in creeps]
        self.fc2 = [tf.nn.tanh(tf.matmul(f, self.var['W2']) + self.var['b2']) for f in self.fc1]
        
        features, weights = [], []
        for f in self.fc2:
            part1, part2 = tf.split(f, num_or_size_splits=2, axis=1)
            
            features.append(part1)
            weights.append(part2)
        
        self.features = tf.stack(features, axis=2)
        self.weights = tf.stack(weights, axis=2)
        
        self.max_weight = tf.reduce_max(self.weights, axis=2, keep_dims=True)
        self.norm_weights = tf.exp(self.weights - self.max_weight)
        self.norm_weights = self.norm_weights / tf.reduce_sum(self.norm_weights, axis=2, keep_dims=True)
        
        self.fc2_weighted = tf.reduce_sum(self.norm_weights * self.features, axis=2)
        
        self.fc3 = tf.nn.tanh(tf.matmul(self.fc2_weighted, self.var['W3']) + self.var['b3'])
        self.fc4 = tf.matmul(self.fc3, self.var['W4']) + self.var['b4']
        
        self.target = tf.placeholder(dtype=tf.float32, shape=[None])
        if net_type == VALUE_NET:
            self.v = tf.reshape(self.fc4, shape=[-1])
            self.delta = self.target - self.v
        
            self.clipped_delta = tf.where(tf.abs(self.delta) < 1.0, 0.5 * tf.square(self.delta), tf.abs(self.delta) - 0.5)
            
            self.loss = tf.reduce_mean(self.clipped_delta)
            
        else: #policy net
            self.action_softmax = tf.nn.softmax(self.fc4)
            
            self.entropy = -tf.reduce_sum(self.action_softmax * tf.log(self.action_softmax), axis=1)
            self.entropy = tf.reduce_mean(self.entropy)
            
            self.action = tf.placeholder(dtype=tf.int32, shape=[None])
            action_one_hot = tf.one_hot(self.action, 9) 
            self.action_p = tf.reduce_sum(self.action_softmax * action_one_hot, reduction_indices=1)
                                   
            self.loss = -(tf.log(self.action_p) * self.target + 0.01 * self.entropy)
            self.loss = tf.reduce_mean(self.loss)
            
        self.optim = tf.train.RMSPropOptimizer(
                      learning_rate=0.001, momentum=0.95, epsilon=0.01).minimize(self.loss)
             
    def get_weights(self, sess):
        print("Getting Weights", file=sys.stderr)
        data = { k : sess.run(self.var[k]).tolist() for k in self.var.keys() }
        return data       
     
    def set_weights(self, sess, weights):
        print("Setting Weights", file=sys.stderr)
        for k,v in weights.items():
            var = self.var[k]
            value = np.array(v, dtype=np.float32)
            sess.run(tf.assign(var, value))
        
class Memory:
    def __init__(self):
        self.curr_idx = 0
        self.mem_size = 1024
        self.mem = np.array([None for _ in range(self.mem_size)], dtype=np.object)
        self.priority = np.array([0 for _ in range(self.mem_size*2-1)], dtype=np.float32)
        self.priority_max = 1000
        self.batch_size = 32
        self.batch_idx = np.zeros(self.batch_size, dtype=np.int32)
        
    def full(self):
        return self.mem[self.curr_idx] != None
        
    def insert(self, data):
        self.mem[self.curr_idx] = data
        
        leaf = self.mem_size - 1 + self.curr_idx
        self.priority[leaf] = self.priority_max
        self.update_priority(leaf)
        
        self.curr_idx = (self.curr_idx + 1) % self.mem_size
        
    def update_priority(self, leaf):
        parent = (leaf + 1) // 2 - 1
        while parent >= 0:
            child_right = (parent + 1) * 2
            child_left = child_right - 1
            
            self.priority[parent] = self.priority[child_left] + self.priority[child_right]
            
            parent = (parent + 1) // 2 - 1
            
    def get_batch(self):
        batch_priority = np.random.rand(self.batch_size) * self.priority[0]
        for i in range(self.batch_size):
            priority = batch_priority[i]
            parent = 0
            while parent < self.mem_size - 1:
                child_right = (parent + 1) * 2
                child_left = child_right - 1
                
                if priority <= self.priority[child_left]:
                    parent = child_left
                else:
                    parent = child_right
                    priority -= self.priority[child_left]
            
            self.batch_idx[i] = parent - self.mem_size + 1
            
        return self.mem[self.batch_idx]
        
    def update_batch_td_error(self, td_error):
        priority = np.abs(td_error)
        for i in range(self.batch_size):
            leaf = self.mem_size - 1 + self.batch_idx[i]
            self.priority[leaf] = priority[i]
            self.update_priority(leaf)