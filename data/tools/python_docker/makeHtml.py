#!/usr/bin/env python
 
import os
import sys
from jinja2 import Environment, FileSystemLoader

# Input block  
tempPath = os.path.dirname(os.path.abspath(__file__))
inputFolder = sys.argv[1]
outputFolder = sys.argv[2]
seqName = sys.argv [3]
# Build environment for rendering
template_env = Environment(
    autoescape=False,
    trim_blocks=False,
    loader=FileSystemLoader(os.path.join(tempPath, 'templates'))
    )
# Search for all dotplot pictures in the input directory
def getDotPlots():
    
    png = []
    
    for file in os.listdir(inputFolder):
        if file.endswith("cov.png"):
            png.append(file)
    
    png.sort()
    return png

# Search for all barchart pictures in the input directory
def getBarChart():
    
    png = []
    
    for file in os.listdir(inputFolder):
        if file.endswith(".png"):
            if not file.endswith("cov.png"):
                png.append(file)
    
    png.sort()
    return png

# Render the given template / Fill the template with all data given by create_html() 
def render_template(template_filename, context):
    return template_env.get_template(template_filename).render(context)
# Get all the pictures, stuff them into the template (render) and create the html 
def create_html():
    fname = os.path.join(outputFolder,'out.html')
    dotP = getDotPlots()
    barC = getBarChart()
    context = {
        'dotP': dotP,
	'barC': barC,
	'seqName' : seqName
    }
    #

    with open(fname, 'w') as f:
        html = render_template('index.html', context)
        f.write(html)
 
 
def main():
    create_html()

 
if __name__ == "__main__":
    main()
