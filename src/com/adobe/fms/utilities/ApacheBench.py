'''
Created on 19 Sep 2011

@author: wallace
'''
import subprocess
from com.adobe.fms.settings import settings

class ApacheBench(object):

    @staticmethod
    def run(frag, frag_dur, num_req, concurrency, stream_url):
        
        output = subprocess.check_output(settings.apache_bench +
                                         ' -d -n' + str(num_req) + ' -c ' + str(concurrency)
                                         + ' ' + stream_url,
                                         stderr=subprocess.PIPE, shell=True)
        lines = output.splitlines()
               
        return lines
    
    @staticmethod 
    def get_time_taken(lines, debug = False):
        for line in lines:
            time_taken_line = line.split(":")
            if  time_taken_line[0] == 'Time taken for tests':
                time_taken_val = time_taken_line[1].strip(' ')
                time_taken = time_taken_val.split(' ')
                if debug is True:
                    print line
                    
                return float(time_taken[0].strip(' '))
        return 0;
    
    @staticmethod 
    def get_total_requests(lines, debug = False):
        for line in lines:
            total_requests_line = line.split(":")
            if  total_requests_line[0] == 'Complete requests':
                if debug is True:
                    print line
                return int(total_requests_line[1].strip(' '))
        return 0;

    @staticmethod 
    def get_requests_per_second(lines, debug = False):
        for line in lines:
            requests_per_second_line = line.split(":")
            if  requests_per_second_line[0] == 'Requests per second':
                requests_per_second_val = requests_per_second_line[1].strip(' ')
                requests_per_second = requests_per_second_val.split(' ')
                if debug is True:
                    print line
                return float(requests_per_second[0])
        return 0;

    @staticmethod 
    def get_latency(lines, debug = False):
        for line in lines:
            lantency_line = line.split(":")   
            if  lantency_line[0] == 'Time per request' :
                latency_text = lantency_line[1].strip(' ')
                latency = latency_text.split(' ')
                if latency[2] == '(mean)':
                    if debug is True:
                        print line
                    return float(latency[0])
        return 0;
    
    @staticmethod    
    def get_non_2xx_responses(lines, debug = False):
        for line in lines:
            non_2xx_responses_line = line.split(":")
            if  non_2xx_responses_line[0] == 'Non-2xx responses':
                if debug is True:
                    print line
                return int(non_2xx_responses_line[1].strip(' '))
        return 0;
                
