'''
Created on 2 Nov 2011

@author: wallace
'''

import sys
import os
sys.path.append(os.path.normpath(os.environ['HDS_LT_PATH']))
import time
import Queue
import threading
import multiprocessing
from com.adobe.fms.utilities.hds import hds
from com.adobe.fms.settings import settings
from com.adobe.fms.utilities.ApacheBench import ApacheBench

# Number of requests for AB
num_req = settings.num_req
# Concurrent requests for AB
concurrency = settings.concurrency

# HDS Origin name/port 
server_name = settings.server_name

# MLM URL
mlm_url = settings.mlm_url

# Write a plain text version of bootstrap to disk
WRITE_TO_DISK = settings.WRITE_TO_DISK

#Max thread pool sizes
MAX_BOOSTRAP_THREAD_COUNT = 120
MAX_FRAGMENT_THREAD_COUNT = 120
MAX_LOG_THREAD_COUNT      = 120

class TestConsumer(threading.Thread):
    
    def __init__(self, task_queue):        
        threading.Thread.__init__(self)
        self.task_queue = task_queue

    def run(self):
        while True:
            next_task = self.task_queue.get()
            next_task()
        return

class TestTask(object):
    
    def __init__(self, level, msg):
        self.level  = level
        self.msg    = msg
        
    def __call__(self):
        t = time.localtime()
        h = str(t.tm_hour < 10 and '0' + str(t.tm_hour) or t.tm_hour)
        m = str(t.tm_min < 10 and '0' + str(t.tm_min) or t.tm_min)
        s = str(t.tm_sec < 10 and '0' + str(t.tm_sec) or t.tm_sec)
        output_time = '%s:%s:%s' % (h,m,s)
        FILE = open(settings.log, "ab")
        FILE.write('[' + output_time + '][' + self.level + '] ' + self.msg + '\n')
        FILE.close()

class LogConsumer(threading.Thread):
    
    def __init__(self, task_queue):        
        threading.Thread.__init__(self)
        self.task_queue = task_queue

    def run(self):
        while True:
            next_task = self.task_queue.get()
            next_task()
        return

class LogTask(object):
    
    def __init__(self, stream_name, frag_num, latency, throughput, non200s):
        self.stream_name    = stream_name
        self.frag_num       = frag_num
        self.latency        = latency
        self.throughput     = throughput
        self.non200s        = non200s
        
    def __call__(self):
        print 'Writing log line for %s-%s' % (self.stream_name, self.frag_num)
        FILE = open(os.path.normpath(settings.bootstrap_dir + '/'+ self.stream_name + '.csv'), "ab")
        FILE.write(self.latency + ',' + self.throughput + ',' + self.non200s + '\n')
        FILE.close()  

class FragmentConsumer(threading.Thread):
    
    def __init__(self, task_queue, result_queue, logging_queue):
        threading.Thread.__init__(self)
        self.task_queue = task_queue
        self.result_queue = result_queue
        self.logging_queue = logging_queue
        
    def run(self):
        while True:
            
            next_task = self.task_queue.get()
            answer = next_task()
            if answer is not None:
                self.logging_queue.put(LogTask(answer.__getitem__('name'), answer.__getitem__('fragment'), answer.__getitem__('latency'), answer.__getitem__('throughput'), answer.__getitem__('non200')))
                self.result_queue.put(answer)
        return

class FragmentTask(object):
    
    def __init__(self, frag_num, frag_dur, num_req, concurrency, stream_url, stream_name, frag_list, discontinuity):
        self.frag_num       = frag_num
        self.frag_dur       = frag_dur
        self.stream_url     = stream_url
        self.stream_name    = stream_name
        self.num_req        = num_req
        self.concurrency    = concurrency
        self.frag_list      = frag_list
        self.discontinuity  = discontinuity
        self.result         = []
        
    def __call__(self):
        
        if self.frag_dur != 0:
            test_info.put(TestTask('INFO', ('Load testing %s-%s with duration of %s msec' % (self.stream_name, self.frag_num, self.frag_dur))))
            print 'Load testing %s-%s with duration of %s msec' % (self.stream_name, self.frag_num, self.frag_dur)
            self.result = ApacheBench.run(self.frag_num, self.frag_dur, self.num_req, self.concurrency, self.stream_url)
            return {'name': self.stream_name,
                    'latency': str(ApacheBench.get_latency(self.result)),
                    'throughput': str(ApacheBench.get_requests_per_second(self.result)),
                    'non200': str(ApacheBench.get_non_2xx_responses(self.result)),
                    'fragment':str(self.frag_num)}
        else:
            return                 

class BootstrapConsumer(threading.Thread):
    
    def __init__(self, task_queue, result_queue, fragment_queue):
        threading.Thread.__init__(self)
        self.task_queue     = task_queue
        self.result_queue   = result_queue
        self.fragment_queue = fragment_queue
        
    def run(self):
        while True:
            next_task = self.task_queue.get()
                        
            answer = next_task()
            if answer is not None:
                seg       = answer.__getitem__('segment')   
                dur       = answer.__getitem__('duration')
                frag      = answer.__getitem__('number')
                name      = answer.__getitem__('name')
                url       = answer.__getitem__('stream_url')
                frag_list = answer.__getitem__('frag_list')
                
                # Loop through current fragment list and add un-pulled, continuous fragments to 
                for frags in frag_list:
                    if frags.__getitem__('pulled') is False:
                        self.fragment_queue.put(FragmentTask(frags.__getitem__('fragment'),
                                                             frags.__getitem__('duration'),
                                                             num_req, concurrency,
                                                             url + 'Seg' + str(frags.__getitem__('segment')).replace(' ', '') + '-Frag' + str(frags.__getitem__('fragment')),
                                                             name, frag_list, int(frags.__getitem__('discontinuity'))))
                        frags.update({'pulled': True})                        
                        time.sleep((int(frags.__getitem__('duration'))/1000) < 2 and 1 or (int(frags.__getitem__('duration'))/1000)-0.5)

                #Sleep before pulling updated bootstrap
                time.sleep(1)
                self.task_queue.put(BootstrapTask(url, name, dur, frag_list))                
                self.result_queue.put(answer)
        return

class BootstrapTask(object):
    
    def __init__(self, baseURL, stream_name, duration, frag_list):
        self.baseURL = baseURL
        self.stream_name = stream_name
        self.duration    = duration
        self.frag_list  = frag_list

        self.bootstrap_url   = 'http://' + server_name + '/hds-live/streams/livepkgr/streams/_definst_/' + stream_name + '/' + stream_name
        self.stream_url      = 'http://' + server_name + '/hds-live/streams/livepkgr/streams/_definst_/' + stream_name + '/' + stream_name        
        self.segment_num  = 0
        self.fragment_num = 0
        self.fragment_dur = 0
        
    def __call__(self):
        
        # Request the bootstrap 
        b_req = hds.request_live_bootstrap(self.bootstrap_url)
        
        if b_req is not False:    
            # Write bootstrap to disk
            hds.write_bootstrap_to_file(settings.bootstrap_dir, self.stream_name, b_req)
                
            # Extract fragment durations
            fragment = hds.extract_fragments(self.stream_name,
                                                hds.convert_manifest(settings.packager,
                                                                    settings.bootstrap_dir,
                                                                    self.stream_name, WRITE_TO_DISK),
                                                                    self.frag_list, True)
            self.segment_num  = fragment[0][0]
            self.fragment_num = fragment[0][1]
            self.fragment_dur = fragment[0][2]
            self.frag_list    = fragment[0][3]
            discontinuity     = fragment[0][4]
            
            return {'name': self.stream_name,
                    'number': fragment[0][1],
                    'segment': fragment[0][0],
                    'duration': fragment[0][2],
                    'stream_url':self.stream_url,
                    'frag_list':  self.frag_list,
                    'discontinuity': discontinuity}
        else:
            test_info.put(TestTask('ERROR', ('Bootstrap for %s could not be loaded. Verify %s.bootstrap to ensure it can be reached.' % (self.stream_name, self.bootstrap_url))))
            print ('Bootstrap for %s could not be loaded. Verify %s.bootstrap to ensure it can be reached.' % (self.stream_name, self.bootstrap_url))
            
            return

if __name__ == '__main__':
    
    # Establish communication queues
    fragments           = Queue.Queue()
    bootstraps          = Queue.Queue()
    bootstrap_results   = Queue.Queue()
    fragment_results    = Queue.Queue()
    logs_to_write       = Queue.Queue()
    test_info           = Queue.Queue()
    
    # Request the live multi-level manifest
    m_req = hds.request_manifest(mlm_url)
    
    #Start logging thread
    test_info_num_consumers = 1
    test_info.put(TestTask('INFO', ('Creating Internal log %d consumers' % test_info_num_consumers)))
    print ('Creating Internal log %d consumers' % test_info_num_consumers)
    test_info_consumers = [ TestConsumer(test_info)
                      for i in xrange(test_info_num_consumers) ]
    
    for w in test_info_consumers:
            w.start()
            
    if m_req is not False:
        # Parse multi-level manifest and extract stream names
        m_bin = hds.parse_live_mlm(m_req)
        bootstrap_list = []
        i = 0
        for item in m_bin:
            if i == 0:
                base_url = item
            else:
                for key, val in item.iteritems():
                    if key == 'href':
                        stream_name = val.split('.')
                        #populate queue with data
                        bootstrap_list.append({'base' : base_url, 'stream' : stream_name[0]})
                        frag_list = []
                        frag_list.append({'segment':0,'fragment':0,'duration':0,'discontinuity':0,'pulled':True})
                        bootstraps.put(BootstrapTask(base_url, stream_name[0], 0.1, frag_list))  
            i += 1
        
        # Spawn consumer threads
        bootstrap_num_consumers = (len(bootstrap_list) > MAX_BOOSTRAP_THREAD_COUNT) and MAX_BOOSTRAP_THREAD_COUNT or len(bootstrap_list) 
        fragment_num_consumers  = (len(bootstrap_list) > MAX_FRAGMENT_THREAD_COUNT) and MAX_FRAGMENT_THREAD_COUNT or len(bootstrap_list)
        #(multiprocessing.cpu_count() < len(bootstrap_list) and len(bootstrap_list) * 2 or multiprocessing.cpu_count() * 2)
        log_num_consumers = (len(bootstrap_list) > MAX_LOG_THREAD_COUNT) and MAX_LOG_THREAD_COUNT or len(bootstrap_list)
        
        test_info.put(TestTask('INFO', ('Creating Bootstrap %d consumers' % bootstrap_num_consumers)))    
        print ('Creating Bootstrap %d consumers' % bootstrap_num_consumers)
        bootstrap_consumers = [ BootstrapConsumer(bootstraps, bootstrap_results, fragments)
                      for i in xrange(bootstrap_num_consumers) ]
                      
        test_info.put(TestTask('INFO', ('Creating Fragment %d consumers' % fragment_num_consumers)))
        print ('Creating Fragment %d consumers' % fragment_num_consumers)
        fragment_consumers = [ FragmentConsumer(fragments, fragment_results, logs_to_write)
                      for i in xrange(fragment_num_consumers) ]
        
        test_info.put(TestTask('INFO', ('Creating Log %d consumers' % log_num_consumers)))
        print ('Creating Log %d consumers' % log_num_consumers)
        log_consumers = [ LogConsumer(logs_to_write)
                      for i in xrange(log_num_consumers) ]
        
        for w in bootstrap_consumers:
            w.start()
            
        for w in fragment_consumers:
            w.start()
        
        for w in log_consumers:
            w.start()    
        
        i=0
        while True: 
            for i in xrange(len(bootstrap_list)):
                if i < len(bootstrap_list):
                    result = bootstrap_results.get()
                    dur    = result.__getitem__('duration')
                    frag   = result.__getitem__('number')
                    name   = result.__getitem__('name')
                    url    = result.__getitem__('stream_url')
                    url    = bootstrap_list[i].__getitem__('base')
                    name   = bootstrap_list[i].__getitem__('stream')
                       
            if i == len(bootstrap_list):
                i = 0    
            i += 1
            
    else:
        test_info.put(TestTask('ERROR', ('Multi-level Manifest could not be loaded. Verify %s.f4m to ensure it can be reached.' % mlm_url)))
        print ('Multi-level Manifest could not be loaded. Verify %s.f4m to ensure it can be reached.' % mlm_url)
