'''
Created on 17 Sep 2011

@author: wallace
'''

import subprocess
import urllib2
from xml.dom import minidom as md
from base64 import decodestring
import os

class hds(object):

    # Requests VOD bootstrap files 
    @staticmethod
    def request_manifest(url):
        try:
            request = urllib2.Request(url + '.f4m')
            response = urllib2.urlopen(request)
            content = response.read()
            response.close()
            return content
        
        except urllib2.HTTPError, error:
            #content = str(error.read())
            return False
        
    # Requests live bootstrap file. This method requires an 
    # additional Directory directive in httpd.conf to allow
    # access to the .bootstrap file in the streams folder
    @staticmethod
    def request_live_bootstrap(url):
        try:

            request = urllib2.Request(url + '.bootstrap')
            response = urllib2.urlopen(request)
            content = response.read()
            response.close()
            return content
        
        except urllib2.HTTPError, error:
            
            #content = str(error.read())
            return False
        
    # Parse the live multi-level manifest
    @staticmethod
    def parse_live_mlm(content):
        elements = []
        
        dom = md.parseString(content)
        baseURLTag = dom.getElementsByTagName('baseURL')[0]
        elements.append((baseURLTag.childNodes[0].data).strip())
        
        mediaTag = dom.getElementsByTagName('media')

        for mediaElement in mediaTag:
            
            bitrate = mediaElement.getAttribute('bitrate')
            #print bitrate
            href = mediaElement.getAttribute('href')
            #print href
             
            temp = {'bitrate': bitrate,
                    'href': href}  
                                              
            elements.append(temp)

        return elements
        
    # Parses the manifest and extracts and converts the bootstrap data to binary        
    @staticmethod    
    def parse_manifest(content):
        dom = md.parseString(content)
        bootstrapInfoTags = dom.getElementsByTagName('bootstrapInfo')[0]
        bootstrapInfoData = (bootstrapInfoTags.childNodes[0].data).strip()
        clean = decodestring(bootstrapInfoData)
        return clean
    
    # Create a local bootstrap file with the binary data       
    @staticmethod   
    def write_bootstrap_to_file(bootstrap_dir, file_name, data):
        FILE = open(bootstrap_dir + '/'+ file_name + '.bootstrap', "wb")
        FILE.write(data)
        FILE.close()
        
    # Convert the manifest to XML 
    @staticmethod 
    def convert_manifest(packager, bootstrap_dir, file_name, log=False):
        output = subprocess.check_output(packager +
                                         ' --inspect-bootstrap --input-file=' +
                                         os.path.normpath(bootstrap_dir + '/' + file_name + '.bootstrap'),
                                         shell=True)
        manifest = output.splitlines()
        if log is True:
            FILE = open(os.path.normpath(bootstrap_dir + '/'+ file_name + '.xml'), "wb")
            FILE.write(output)
            FILE.close()
        return manifest
    
    # Extract the segment section from the bootstrap
    @staticmethod 
    def extract_segment_section(boostrap):
        segment_run_table = []
        segment_start = 0
        fragment_start = 0
        i = 0
        for line in boostrap:
            search_val = line.split(":")

            if search_val[0] == 'segments':
                segment_start = i + 5
            if search_val[0] == 'fragments':
                fragment_start = i
                break
            i += 1
        i = segment_start
        for j in xrange(segment_start, fragment_start):   
            segment_run_table.append(boostrap.pop(i))
        return segment_run_table 
    
    # Extract the fragment section from the bootstrap
    @staticmethod 
    def extract_fragment_section(bootstrap):
        fragment_run_table = []
        fragment_start = 0
        fragment_end = len(bootstrap)
        i = 0
        for line in bootstrap:
            search_val = line.split(":")
            if search_val[0] == 'fragments':
                fragment_start = i + 5
                break
            i += 1
        i = fragment_start
        for j in xrange(fragment_start, fragment_end):   
            fragment_run_table.append(bootstrap.pop(i))
        return fragment_run_table  
    
    @staticmethod
    def check_for_dups(frag, arr):
        for i in arr:
            if i.__getitem__('fragment') == frag:
                return True
        return False
    
    @staticmethod
    def is_in_fragment_run_table(frag, arr):
        j=0
        for i in arr:
            temp_frag = i.split(',') 
            temp_fragment_num  = temp_frag[0].split('=')
            if int(temp_fragment_num[1]) == frag:
                return j
            j+=1
        return False
            
    # This method checks the integrity of the bootstrap
    # and inserts/fixes fragments that are missing or 
    # are discontinuous
    @staticmethod          
    def extract_fragments(file_name, run_table, check_frag, live=False):
        durations = []
        i = 0
        frag_num_check = 0
        discon = 0
        if live is True:      
            # Extract the increasing number 
            # of fragments from the segment run table
            segments = hds.extract_segment_section(run_table)
            total_num_of_frag_in_seg = 0
            #Get last entry in segment run table i.e. the most recent           
            if len(segments) > 1:
                for segment in segments:
                    temp = segment.split(',')        
                    total_num_of_frag_in_seg += int(temp[1].split('=')[1])
                    segment_num = temp[0].split('=')
            else:
                temp = segments[len(segments)-1].split(',') 
                total_num_of_frag_in_seg += int(temp[1].split('=')[1])
                segment_num = temp[0].split('=')
            
                
            # Extract fragment number and duration
            # from fragment run table
            fragments = hds.extract_fragment_section(run_table)
           
            #Get last entry in fragment run table i.e. the most recent
            temp         = fragments[len(fragments)-1].split(',') 
            duration      = temp[2].split('=') 
            fragment_num  = temp[0].split('=')
            
            # Check for fragment discontinuity
            discontinuity = 0
            if len(temp) == 4:
                discontinuity_check = temp[3].split('=')
                discontinuity = discontinuity_check[1]
                discon = discontinuity
            if len(run_table) > 1:
                # Calc distance between oldest and newest fragments in run table
                inital_frag_line = fragments[0].split(',')
                inital_frag      = inital_frag_line[0].split('=') 
                frag_diff        = int(fragment_num[1]) - int(inital_frag[1])
                # Calc distance between oldest fragment in run table and newest fragment (not necessarily in run table)
                current_frag = (int(total_num_of_frag_in_seg) - frag_diff) + int(fragment_num[1])-1
            else:
                # Use the incrementor
                current_frag = int(total_num_of_frag_in_seg)+ int(fragment_num[1])-1
            
            # First run
            if len(check_frag) == 1:
                check_frag.append({'segment':segment_num[1], 'fragment': current_frag, 'duration': int(duration[1]), 'discontinuity': int(discontinuity), 'pulled':False})
            else: 
                frag_gap = current_frag - check_frag[len(check_frag)-1].__getitem__('fragment')
                
                miss_frag = int(current_frag)
                missing_frag_arr = []
                if frag_gap != 1:
                    #Get missing fragments
                    for i in xrange(len(check_frag)-1, len(check_frag) + (frag_gap-1)):
                        miss_frag -= 1
                        if hds.check_for_dups(miss_frag, check_frag) is False:    
                                
                            missing_frag_arr.append({'missing': miss_frag})
                            to_add = {'segment':segment_num[1],'fragment': miss_frag, 'duration': int(duration[1]), 'discontinuity': int(discontinuity), 'pulled':False}
                            #Check if there is a corresponding fragment in the run table
                            fragle = hds.is_in_fragment_run_table(miss_frag, fragments)
                            if fragle is not False:
                                temp_frag = fragments[fragle].split(',') 
                                temp_fragment_num  = temp_frag[0].split('=')
                                temp_duration      = temp_frag[2].split('=') 
                                    
                                temp_discontinuity = 0
                                # Check for fragment discontinuity
                                if len(temp_frag) == 4:
                                    temp_discontinuity_check = temp_frag[3].split('=')
                                    temp_discontinuity = temp_discontinuity_check[1]
                                    discon = temp_discontinuity
                                to_add = {'segment':segment_num[1], 'fragment': miss_frag, 'duration': int(temp_duration[1]), 'discontinuity': int(temp_discontinuity), 'pulled':False}
                                
                            check_frag.append(to_add)
            
            #sorted(check_frag, key=lambda k: k['fragment'])
            if len(check_frag) > 20:
                small_list = check_frag[len(check_frag)-21:len(check_frag)-1]
#            for all in check_frag:
#                if all.__getitem__('pulled') is False:
#                    small_list.append(all)
            
            durations.append([segment_num[1], current_frag, int(duration[1]), sorted(check_frag, key=lambda k: k['fragment']), discon])
            
            return durations
        
        else:
        #for line in run_table:
           
            # Extract fragment number (for live) and duration
            # from fragment run table
            
            # Extract the increasing number 
            # of fragments from the segment run table
            segments = hds.extract_segment_section(run_table)
            
            #Get last entry in segment run table i.e. the most recent
            temp = segments[len(segments)-1].split(',')    
            total_num_of_frag_in_seg = temp[1].split('=')
            
            # Extract fragment number and duration
            # from fragment run table
            fragments = hds.extract_fragment_section(run_table)
            
            for fragment in fragments:
                
                
                temp          = fragment.split(',') 
                duration      = temp[2].split('=') 
                fragment_num  = temp[0].split('=')
                
                # Check for fragment discontinuity
                temp_discontinuity = 0
                if len(temp) == 4:
                    temp_discontinuity_check = temp[3].split('=')
                    temp_discontinuity = temp_discontinuity_check[1]
                    
                check_frag.append({'fragment': int(fragment_num[1]), 'duration': int(duration[1]), 'discontinuity': int(temp_discontinuity), 'pulled':False})
            return check_frag                  
