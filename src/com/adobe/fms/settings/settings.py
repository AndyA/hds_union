'''
Created on 19 Sep 2011

@author: wallace
'''
import os

# HDS Origin name/port 
server_name = 'localhost' 

# MLM URL
mlm_url = 'http://' + server_name + '/vod/liveevent1' #excluding .f4m

# Number of requests for AB
num_req = 100
# Concurrent requests for AB
concurrency = 10

# Write a plain text version of bootstrap to disk
WRITE_TO_DISK = True

apache_bench = (os.name == 'nt' and os.path.normpath('../../../../../apache_bench/ab.exe') or 'ab')             

bootstrap_dir = os.path.normpath('../../../../../bootstrap/')

packager = (os.name == 'nt' and os.path.normpath('../../../../../f4fpackager/win/f4fpackager.exe') or os.path.normpath('../../../../../f4fpackager/linux/f4fpackager'))

log = os.path.normpath('../../../../../logs/debug.log')      
