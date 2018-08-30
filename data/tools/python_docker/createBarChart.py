import matplotlib as mpl
# .use('Agg') for hard-coded backend when running per ssh without display variable 
mpl.use('Agg')
import matplotlib.pyplot as plt; plt.rcdefaults()
import numpy as np
import os 
import sys

# Import path 
pathToDir = sys.argv[1]
# Get all the files in a directory
dirList = os.listdir(pathToDir)
# Array for entries of format [file_name : numer_of_entries_above_thresshold]
dataArray = []
# If values not given, use default
filter_1 = sys.argv[2] if len(sys.argv) >= 3 else 1.0
# Coverage(subject)
filter_1_place = 15
filter_2 = sys.argv[3] if len(sys.argv) >= 4 else 98
# Identity
filter_2_place = 2
titel_x = "Titel x"
titel_y = "Anzahl:"

#for every file in the input directory
for dir in dirList:
    # Find all .cov files
    if dir.endswith(".cov"):
        # Fix pathToDir to get a proper path when a file name is added to the path
        if not pathToDir.endswith("/"):
            pathToDir = pathToDir+"/"
        # Open every .cov file in the input directory 
        with open(pathToDir + dir, 'r') as f:

            # Single entry which will be added to dataArray
            buffer = []
            # Counter of all lines that are above thresshold 
            counter = 0
            # Append the file name 
            buffer.append(dir)
            # For every line in a .cov file
            for line in f:
                # clean and split by tabs to get all columns 
                line_buffer = line.rstrip().split('\t')
                # If line is above thresshold, count this line 
                if float(line_buffer[filter_1_place]) >= float(filter_1) and float(line_buffer[filter_2_place]) >= float(filter_2):
                    counter += 1

            buffer.append(counter)

            dataArray.append(buffer)

# Data to plot
groups = len(dataArray)

# Create plot
# antibiotic-group names for the x-axis
objects = ()
# hits for the y-axis
performance = []
# function used to sort the dataArray
def getKey(item):
    return item[0]
# Sort the array to get a plot with sorted entries
dataArray = sorted(dataArray, key=getKey)

# Every .cov file starts with the name of the base-file it is created from
# Get this base-file name
titel_x = ''.join(dataArray[0][0].split('.')[0].split('_')[:-2])
# For every entry in dataArray
for box in dataArray:
    # Get the used antibiotic-group from the file name
    objects = objects + (box[0].split('.')[0].split('_')[-2],)
    # simple debugging output: antibiotic-group_name + hit_count
    print(box[0].split('.')[0].split('_')[-2]+"\t"+str(box[1]))
    # Get the number of hits above thresshold for the y-axis
    performance.append(box[1])
# Get number of slots reserved for the y-axis
y_pos = np.arange(len(objects))
# plot configuration
plt.bar(y_pos, performance, align='center', alpha=0.8, color='r')
plt.xticks(y_pos, objects, rotation='vertical')
plt.yticks(np.arange(0, max(performance)+1, 2))
plt.ylabel(titel_y)
plt.title(titel_x)

# Tweak spacing to prevent clipping of tick-labels
plt.subplots_adjust(bottom=0.25)
plt.suptitle("Param: "+str(filter_1_place)+" >= "+str(filter_1)+" - "+str(filter_2_place)+" >= "+str(filter_2))
# Set labels with score above each bar 
for x, y in enumerate(performance):
        plt.gca().text(x, y + .15, str(y), color='grey', ha='center', fontsize=6)

# Show a faint background-grid
plt.grid(which='major', linestyle='--', linewidth='0.2', color='gray', alpha=0.2, axis='y')

plt.plot()
plt.savefig(pathToDir+titel_x+"_"+str( filter_1_place )+"_"+str(filter_1)+"_"+str( filter_2_place )+"_"+str( filter_2 )+".png", dpi=600)
#plt.show()
