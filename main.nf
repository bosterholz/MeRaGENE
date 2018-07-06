#!/usr/bin/env nextflow

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
 */

// Basic parameters. Parameters defined in the .config file will overide these
params.input = "$baseDir/data/test_data/genome/clostridium_botulinum.fasta"
params.blast = 'blastn'
params.blast_cpu = 8
params.blast_db = "$baseDir/data/test_data/resFinderDB_19042018"
params.outputFolder = "$baseDir/out"
params.help = ''
params.nfRequiredVersion = '0.30.0'
params.version = '0.1.1'

// Check if the used Nextflow version is compatible 
if( ! nextflow.version.matches(">= ${params.nfRequiredVersion}") ){
  println("Your Nextflow version is too old, ${params.nfRequiredVersion} is the minimum requirement")
  exit(1)

params.help = ''}

// Show the help page if the --help tag is set while caling the main.nf
if (params.help) exit 0, help()

// First Message that pops up, showing the used parameters and the MeRaGENE version number 
runMessage()

// Set input parameters:
query = file(params.input)
outDir = file(params.outputFolder).mkdir() 
blast_db = file(params.blast_db)

if( !query.exists() ) exit 1, "The input file does not exist: ${query}"
if( !blast_db.exists() ) exit 1, "The input database does not exist: ${blast_db}"

process test {

	echo true

  	script:
  	"echo Hello"
}

// The contend of the help page is defined here:
def help() {
	log.info "----------------------------------------------------------------"
	log.info ""
	log.info " Welcome to the MeRaGENE ~ version ${params.version} ~ help page"	
	log.info "    Usage:"
	log.info "           --help    Call this help page"
}

// The contend of the first message prompt is defined here:
def runMessage() {
	log.info "\n"
	log.info "MeRaGENE ~ version ${params.version}"
	log.info "------------------------------------"
	log.info "input    :${params.input}"
	log.info "output   :${params.outputFolder}"
	log.info "blast_db :${params.blast_db}"
	log.info "\n"
}
