#!/usr/bin/env nextflow

// vim higlighting tag
/*
vim: syntax=groovy
-*- mode: groovy;-*-
*/

/*
 * ###################################################
 * #                  MeRaGENE                       #
 * # Metagenomics rapid gene identification pipeline #
 * ###################################################
 * 
 * @Authors
 * Benedikt Osterholz
 * Peter Belmann 
 * Wiebke Paetzold
 * Annika Fust
 * Madis Rumming
 * Alexander Sczyrba
 * Andreas Schlueter
 */

// Basic parameters. Parameters defined in the .config file will overide these
params.testRun = ''
// If the test run flag ist set, use test input
if (params.testRun){
	params.input_folder = "$baseDir/data/test_data/genome"	
} else {
	// Input folder string must not be completely empty. Empty strings pass the detection, producing errors.
	params.input_folder = "$baseDir/input"
}

params.blast = 'blastx'
params.blast_cpu = 4
// Default e-value copied from blast
params.evalue = '10'
// Pick the right blast-db depending on the blast version used
if( params.blast.equals('blastx') || params.blast.equals('blastp') ){
	params.blast_db = "$baseDir/data/databases/resFinderDB_23082018/*AA.fsa"
} else if( params.blast.equals('blastn') || params.blast.equals('tblastx') || params.blast.equals('tblastn') ) {
	params.blast_db = "$baseDir/data/databases/resFinderDB_23082018/*NA.fsa"
} else {
	println("Your Blast Version is not supported.")
	exit(1)}

params.coverage = '100'
params.identity = '98'
params.output_folder = "$baseDir/out"
params.help = ''
params.nfRequiredVersion = '0.30.0'
params.version = '0.1.27'
params.s3 = ''
params.s3_container = 'MeRaGENE'
// If docker is used the blastDB path will not be included in the volume mountpoint because it is a path, not a file
// This dummy file is inside the databse folder doing the job, so that the path is mounted into the docker instance 
docker_anker = file("$baseDir/data/databases/docker_anker")

// Check if the used Nextflow version is compatible 
if( ! nextflow.version.matches(">= ${params.nfRequiredVersion}") ){
  println("Your Nextflow version is too old, ${params.nfRequiredVersion} is the minimum requirement")
  exit(1)}

// Show the help page if the --help tag is set while calling the main.nf
if (params.help) exit 0, help()

// First Message that pops up, showing the used parameters and the MeRaGENE version number 
runMessage()

// If S3 mode is used the starting query has to come out of S3
if(params.s3){
	// Get S3 input files and create output folder
	process getS3Input{
		
		output:
		file "*" into s3_input

		script:
		"""
		${baseDir}/data/tools/minio/mc cp --recursive openstack/${params.s3_container}/input/ .
		"""
	}

	s3_input.map{ file -> tuple(file.simpleName, file) }.set{ query }
	// Set outDir manually for S3 mode. The outDir has to be set even if not used.
	outDir = file("$baseDir/out") 
}
else{

// Set input parameters if S3 is not selected:
query = Channel.fromPath( "${params.input_folder}/*", type: 'file' )
	.ifEmpty { error "No file found in your input directory ${params.input_folder}"}
	.map { file -> tuple(file.simpleName, file) }
outDir = file(params.output_folder)
} 

// Set general input parameters:
blast_db = Channel.fromPath(params.blast_db, type: 'file' )
		.ifEmpty { error "No database found in your blast_db directory ${params.blast_db}"}

//Check if the input/output paths exist
if( !outDir.exists() && !outDir.mkdirs() ) exit 1, "The output folder could not be created: ${outDir} - Do you have permissions?"

process blast {
	
	// Tag each process with a unique name for better overview/debugging
	tag {seqName + "-" + dbName }
	// If the blast output is not named "empty.blast", a copy is put into the publishDir	
	publishDir "${outDir}/${seqName}", mode: 'copy', saveAs: { it == 'empty.blast' ? null : it }
	
	// Docker blast container which this process is executed in 	
	container 'biocontainers/blast:v2.2.31_cv1.13'
	
	input:
	// Not file(db) so that complete path is used to find the db, not only the linked file 
	each db from blast_db
	set seqName, file(seqFile) from query
	// Has to be a file to include the database folder into the docker volume mount path
	file(docker_anker)

	output:
	set seqName, file("*.blast") into blast_output
	
	script:
	// No channel with sets used, because *each set* do not work together. So baseName is determined in a single step  
	dbName = db.baseName
	// After the input is blasted, the output is checked for contend. If it is empty, it is renamed to "empty.blast" to be removed later. 
  	"""
	head ${docker_anker}
	${params.blast} -db ${db} -query ${seqFile} -num_threads ${params.blast_cpu} -evalue ${params.evalue} -outfmt "6 qseqid sseqid pident length qlen slen mismatch gapopen qstart qend sstart send evalue bitscore qcovs" -out ${seqName}_${dbName}.blast
	if [ ! -s ${seqName}_${dbName}.blast ]; then mv ${seqName}_${dbName}.blast empty.blast; fi 
	"""
}

// Empty blast outputs are removed by this filter step, [1] because it is a set
blast_output.filter{!it[1].isEmpty()}.set{subject_covarage_input}

// Calculate the missing subject covarage and add it to the blast output
process getSubjectCoverage {
	
	echo true
	// Tag each process with a unique name for better overview/debugging
	tag {blast}
	// After process completion a copy of the result is made in this folder 	
	publishDir "${outDir}/${seqName}", mode: 'copy'

	input:
	set seqName, file(blast) from subject_covarage_input

	output:
	set seqName, file("${blast}.cov") into getCoverage_output_dotPlot 
	set seqName, file("${blast}.cov") into getCoverage_output_barChart 

	shell:
	// Calculation: ( ( (SubjectAlignment_End - SubjectAlignment_Start + 1) / SubjectLength) * (Identity/100) ) 
	'''
	while read p; do
		cov=$(awk '{ print ((($12-$11+1)/$6)) }' <<< $p);	
                covId=$(awk '{ print ((($12-$11+1)/$6)*($3/100)) }' <<< $p);
                echo "$p\t$cov\t$covId" >> !{blast}.cov;
        done < !{blast}
	'''
}


// Create a dot plot of the blast-coverage results 
process createDotPlots {

	tag {coverage}
	
	publishDir "${outDir}/${seqName}", mode: 'copy'

	container 'bosterholz/meragene@sha256:29e7c11f2754f22f98be57852de68eeb830cb9fecfc9d7e9bda9f3bc12a9f35c'

	input:
	set seqName, file(coverage) from getCoverage_output_dotPlot

 
	output:
	set seqName, file("*.png") into createPlot_out
	
	// A prebuild executable of the createDotPlot.py is used to execute this process
	script:
	"""
	python /app/createDotPlot.py ${coverage} .  
	"""
}


// Create a dot plot of the blast-coverage results 
process createBarChart {
	
	tag {seqName}

	publishDir "${outDir}/${seqName}", mode: 'copy'

	container 'bosterholz/meragene@sha256:29e7c11f2754f22f98be57852de68eeb830cb9fecfc9d7e9bda9f3bc12a9f35c'
	// For createBarChart.py to work, all blast_cov files have to be present. collect() does not work, creating a multi-set Nextflow cannot handle.
	// So groupTuple() is used collecting all input files, grouping them by their seqName to return a single set (seqName, blast_cov[array])  
	input:
	set val(seqName), file(coverage) from getCoverage_output_barChart.groupTuple()
 
	output:
	set val(seqName), file("*.png") into createChart_out
	
	// Python script which is executed inside the python docker-container. 
	// Input: createBarChart.py "directory with input .cov files" "coverage threshold" "identity threshold"
	script:
	"""
	python /app/createBarChart.py ./ ${params.coverage} ${params.identity} 
	"""
}

// Use all plots and generated results to build an independant output html
process createHTML {
	
	tag {seqName}

	publishDir "${outDir}/${seqName}", mode: 'copy'

	container 'bosterholz/meragene@sha256:29e7c11f2754f22f98be57852de68eeb830cb9fecfc9d7e9bda9f3bc12a9f35c'

	input:
	set val(seqName), file(png) from createChart_out.collect()
	set val(seqName2), file(dotplot) from createPlot_out.groupTuple()
	file(docker_anker)

	output:
	file 'report.html' into s3_upload
	
	// makeHtml is used to feed the input data into a template. The converted finished html has to be saved to /app.
	// In /app there are the "bootstrap" and "vendor" folders webpage2html needs to build an independant html.	
	script:
	"""
	python /app/makeHtml.py ./ ./ "${seqName}"
	cp -r /app/templates/* ./
	python /app/webpage2html.py -s ./out.html > report.html
	"""
}

// If the --s3 flag is set, this part is used to upload the results to s3/swift
if(params.s3){

	process uploadResults {
	
		input:
		file 'finish_*' from s3_upload.collect()

		script:
		"""
		${baseDir}/data/tools/minio/mc cp --recursive $baseDir/out/  openstack/${params.s3_container}/output/
		"""
	}
}

// The contend of the help page is defined here:
def help() {
	log.info "------------------------------------------------------------------------------------"
	log.info ""
	log.info " Welcome to the MeRaGENE ~ version ${params.version} ~ help page"	
	log.info ""
	log.info " Usage:  nextflow main.nf [options] [arg...]"
	log.info ""
	log.info " Options:"
	log.info "           --help      Shows this help page"
	log.info "           --s3        S3/Swift Mode. Input and Output are handled "
	log.info "                       via S3/Swift by a minio client. A project folder"
	log.info "                       located in the object storage root has to be selected."
	log.info "                       This folder will be used to get the input data and upload"
	log.info "                       the results. Use --s3_container \"folder\" to specify."
	log.info "                       The input fasta has to be inside an \"input\" folder "
	log.info "                       in the project folder. The S3/Swift credentials"
 	log.info "                       are added to the \"nextflow.config\" in form of:"
	log.info "                       env.MC_HOSTS_openstack = 'https://ID:KEY@ENDPOINT:PORT'"
	log.info "           --testRun   Test your installation by running MeRaGENE with test data."
	log.info "                       Just set this flag. MeRaGENE will do the rest."	
	log.info ""
	log.info " Arguments:"
	log.info "           --input_folder      Set new input folder path "
	log.info "                               (default: ${params.input_folder})"
	log.info "           --output_folder     Set new output folder path. "
	log.info "                               (default: $baseDir/out)"
	log.info "           --blast             Set the blast version used for this run "
	log.info "                               Supportet: blastn, blastp, blastx, tblastn, tblastx"
	log.info "                               (default: ${params.blast})"
	log.info "           --blast_cpu         Set the amount of cpus used per blast process"
	log.info "                               (default: ${params.blast_cpu})"
	log.info "           --evalue            Set the e-value used for the blast processes"
	log.info "                               (default: ${params.evalue})"
	log.info "           --coverage          Set the coverage threshold used for the barchart plot"
	log.info "                               (default: ${params.coverage} [unit = percent])"
	log.info "           --identity          Set the identity threshold used for the barchart plot"
	log.info "                               (default: ${params.identity} [unit = percent])"
	log.info "           --s3_container      Set the project folder used in S3/Swift mode"
	log.info "                               (default: ${params.s3_container})"
	log.info "                     "
}

// The contend of the overview message prompt is defined here:
def runMessage() {
	log.info "\n"
	log.info "MeRaGENE ~ version " + params.version
	log.info "------------------------------------"
	log.info "config file   : " + workflow.configFiles
	// If S3 mode is used paths are fixed 
	if(params.s3){	
	log.info "input_folder  : S3:/${params.s3_container}/input"
	log.info "output_folder : S3:/${params.s3_container}/output"}
	else{
	log.info "input_folder  : " + params.input_folder
	log.info "output_folder : " + params.output_folder} 
	log.info "blast version : " + params.blast 
	log.info "blast_db      : " + params.blast_db 
	log.info "blast_cpu     : " + params.blast_cpu
	log.info "evalue        : " + params.evalue
	log.info "coverage      : " + params.coverage + " (%)"
	log.info "identity      : " + params.identity + " (%)" 
	log.info "\n"
}

// Overview message prompt after the workflow is finished 
workflow.onComplete {
	this.runMessage()
	log.info "Total runtime : " + workflow.duration
	log.info "Finished at   : " + workflow.complete
	log.info "Success       : " + workflow.success
	log.info "Exit status   : " + workflow.exitStatus
	log.info "Error report  : " + (workflow.errorReport ?: '-')
	log.info "Nextflow      : " + nextflow.version
}

