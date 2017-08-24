import os
os.environ['TF_CPP_MIN_LOG_LEVEL']='2'
import tensorflow as tf
import numpy as np
import sys
import json

class Model:
    def __init__(self):
        tf.reset_default_graph()
        
        self.ep = 0
        self.explore = 5
        self.boot_strap = 0
        self.boot_strap_freq = 5
        self.replace_freq = 10
        self.target_replace_freq = 10
        self.save_freq = 25
        
        self.memory = Memory()
        self.policy_net = Net(POLICY_NET)
        
        self.sess = tf.InteractiveSession()
        self.sess.run(tf.global_variables_initializer())
        
    def get_update(self):
        data = self.policy_net.get_weights(self.sess)
        data['boot_strap'] = self.boot_strap
        data['explore'] = self.explore
        data['replace'] = (self.ep % self.replace_freq) == 0
        return data
        
    def dump(self):
        data = self.policy_net.get_weights(self.sess)
        np.save('dump%d.npy' % self.ep,data)               
        
    def load(self, file):
        print("Loading: " + file, file=sys.stderr)
        data = np.load(file).item()   
        self.policy_net.set_weights( self.sess, data )
        print("Sucess", file=sys.stderr)    
                    
    def run(self,data):
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
                action = np.array(action, dtype=np.float32)
                reward = np.array(reward, dtype=np.float32)
                
                _, policy_loss, log_loss = self.sess.run([self.policy_net.optim,
                                                          self.policy_net.loss,
                                                          self.policy_net.log_loss],
                                                            feed_dict={self.policy_net.target : reward,
                                                                       self.policy_net.s_t : s_t,
                                                                       self.policy_net.action : action})

                print("PLoss: %0.3f" % policy_loss, file=sys.stderr)
        
                self.memory.update_batch_td_error(log_loss)
                
        if not self.memory.full():
            print("Experience %d of %d gathered" % (self.memory.curr_idx, self.memory.mem_size), file=sys.stderr)
        
        if self.explore > 1:
            self.explore -= 0.001

        if self.ep % self.boot_strap_freq == 0:
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
            
            R = d_t['r'] + 0.7*R
            s_t.append(d_t['s'])
            action.append(d_t['a'])
            reward.append(R)
        
        s_t = np.array(s_t, dtype=np.float32)
        action = np.array(action, dtype=np.float32)
        reward = np.array(reward, dtype=np.float32)
        
        reward = np.clip(reward, -2, 2)
        
        return zip(s_t, action, reward)
           
VALUE_NET = 0
POLICY_NET = 1
class Net:
    def __init__(self, net_type):
        self.s_t = tf.placeholder(dtype=tf.float32, shape=[None, 8])
        self.var = {}
        self.var['W1'] = tf.get_variable('W1',shape=[8,256], initializer=tf.contrib.layers.xavier_initializer())
        self.var['b1'] = tf.Variable(tf.zeros([256]), dtype=tf.float32)
        self.var['W2'] = tf.get_variable('W2',shape=[256,128], initializer=tf.contrib.layers.xavier_initializer())
        self.var['b2'] = tf.Variable(tf.zeros([128]), dtype=tf.float32)
        self.var['W3'] = tf.get_variable('W3',shape=[128,60], initializer=tf.contrib.layers.xavier_initializer())
        self.var['b3'] = tf.Variable(tf.zeros([60]), dtype=tf.float32)

        self.fc1 = tf.nn.relu(tf.matmul(self.s_t, self.var['W1']) + self.var['b1'])
        self.fc2 = tf.nn.relu(tf.matmul(self.fc1, self.var['W2']) + self.var['b2'])
        self.fc3 = tf.matmul(self.fc2, self.var['W3']) + self.var['b3']
                
        self.pi, self.mu1, self.mu2 = Net.get_mixture_coef(self.fc3)
                
        self.target = tf.placeholder(dtype=tf.float32, shape=[None])
        self.action = tf.placeholder(dtype=tf.float32, shape=[None, 2])
        self.action_x, self.action_y = tf.split(self.action, num_or_size_splits=2, axis=1)
            
        self.log_loss, self.temp = Net.log_likelihood(self.pi, self.mu1, self.mu2, 5.0, 5.0, 0.0, self.action_x, self.action_y)
        self.loss = tf.reduce_mean(self.log_loss * self.target)
        
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

    def tf_2d_normal(x1, x2, mu1, mu2, s1, s2, rho):
      norm1 = tf.subtract(x1, mu1)
      norm2 = tf.subtract(x2, mu2)
      s1s2 = tf.multiply(s1, s2)
      z = tf.square(tf.div(norm1, s1))+tf.square(tf.div(norm2, s2))-2*tf.div(tf.multiply(rho, tf.multiply(norm1, norm2)), s1s2)
      negRho = 1-tf.square(rho)
      result = tf.exp(tf.div(-z,2*negRho))
      denom = 2*np.pi*tf.multiply(s1s2, tf.sqrt(negRho))
      result = tf.div(result, denom)
      return result

    def log_likelihood(pi, mu1, mu2, sigma1, sigma2, corr, x1_data, x2_data):
      result0 = Net.tf_2d_normal(x1_data, x2_data, mu1, mu2, sigma1, sigma2, corr)
      
      result = tf.multiply(result0, pi)
      result = tf.reduce_sum(result, axis=1, keep_dims=True)
      result = -tf.log(tf.maximum(result, 1e-20)) # at the beginning, some errors are exactly zero.

      return result, result0

    # below is where we need to do MDN splitting of distribution params
    def get_mixture_coef(output):
      z = output
      z_pi, z_mu1, z_mu2 = tf.split(axis=1, num_or_size_splits=3, value=z)

      max_pi = tf.reduce_max(z_pi, axis=1, keep_dims=True)
      z_pi = tf.subtract(z_pi, max_pi)
      z_pi = tf.exp(z_pi)
      normalize_pi = tf.reciprocal(tf.reduce_sum(z_pi, axis=1, keep_dims=True))
      z_pi = tf.multiply(normalize_pi, z_pi)


      return [z_pi, z_mu1, z_mu2]
            
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
            