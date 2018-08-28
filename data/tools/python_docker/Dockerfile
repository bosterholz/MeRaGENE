FROM python:3.4-slim
WORKDIR /app
ADD createDotPlot.py /app
ADD createBarChart.py /app
RUN python -mpip install -U matplotlib
ADD makeHtml.py /app
ADD webpage2html.py /app
ADD templates /app/templates
RUN pip install 'lxml>=3.4.4' 'beautifulsoup4>=4.0.0' 'requests>=2.5.2' 'termcolor>=1.1.0' jinja2
