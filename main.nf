#!/usr/bin/env nextflow

params.vendor = "$baseDir/vendor"
PYTHON="${params.vendor}/python/bin/python"
params.search = ""
params.keywords = ""
params.help = ""
params.faa = ""

if( params.help ) { 
    usage = file("$baseDir/usage.txt")   
    print usage.text
    return 
}

outputDir = file(params.output)
if(outputDir.exists()){
    println "Directory ${outputDir} already exists. Please remove it or assign another output directory."
    return
}

hmmDir = file(params.input)
ncbiDB = file(params.ncbi)
genomeFaa = file(params.genome)


keywordsFile = ""
if(params.keywords){
	keywordsFile = file(params.keywords)
}

searchFile = ""
if(params.search){
	searchFile = file(params.search)
}

process bootstrap {

   executor 'local'

   input:
   params.vendor
   
   output:
   file allHmm

   shell:
   outputDir.mkdir()
   """
   #!/bin/bash
   if [ ! -d !{params.vendor} ]
   then
       make -C !{baseDir} install
   fi
   cat !{hmmDir}/*.hmm > allHmm
   ${params.hmm_press} allHmm
   """
}

fastaChunk = Channel.create()
list = Channel.fromPath(genomeFaa).splitFasta(by:6000,file:true).collectFile();
list.spread(allHmm).into(fastaChunk)

process hmmFolderScan {

    cpus "${params.hmm_cpu}"

    memory '8 GB'
    cache false

    input:
    val chunk from fastaChunk

    output:
    file domtblout

    script:
    fastaChunkFile = chunk[0]
    hmm = chunk[1] 
    """
    #!/bin/sh
    ${params.hmm_scan} -E ${params.hmm_evalue} --domtblout domtblout --cpu ${params.hmm_cpu} -o allOut ${hmm} ${fastaChunkFile}
    """
}
    
params.num = 1
num = params.num

process uniqer {
    
    cache false

    input:
    file domtblout
    params.num
      
    output:
    file outputFasta into fastaFiles

    """
    $baseDir/scripts/uniquer.sh $num domtblout outputFasta
    """    
}

uniq_lines = Channel.create()
uniq_overview = Channel.create()
fastaFiles.filter({it -> java.nio.file.Files.size(it)!=0}).tap(uniq_overview).flatMap{ file -> file.readLines() }.into(uniq_lines)

process getFasta {

    cpus 4
    memory '4 GB'

    input:
    val contigLine from uniq_lines
    
    output:
    file 'uniq_out'
    file 'cut_faa'
    
    script:
    """
    #!/bin/sh
    $PYTHON ${baseDir}/scripts/getFasta.py --i "${contigLine}" --g "${genomeFaa}" --b "${params.output}"
    """  

}

uniq_seq = Channel.create()
uniq_seqHtml = Channel.create()
cut_faa.separate( uniq_seq, uniq_seqHtml ) { a -> [a, a] }

process blastSeqTxt {
    
    cpus 4
    memory '16 GB'
    
    input:
    file uniq_seq

    output:
    file blast_out
    
    script:
    order = "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore sallacc salltitles staxids sallseqid sscinames "
/*
 * blast all fasta sequences against the ncbi database. A special output format is used, to make the data usable for the next pipeline.
 */ 
    shell:
    '''
    #!/bin/sh
    contig=`grep ">" !{uniq_seq} | cut -d" " -f1 | cut -c 2-`
    !{params.blastp} -db !{ncbiDB} -outfmt '!{order}' -query '!{uniq_seq}' -out "!{params.output}/txt_faa_files/$contig.txt" -num_threads !{params.blast_cpu}
    echo "$contig" > blast_out
    '''
}

blast_all = Channel.create()
blast_out
   .collectFile()
   .into(blast_all)

process blastSeqHtml {

    errorStrategy 'ignore'
    cpus 4
    memory '16 GB'

    input:
    file uniq_seqHtml

/*
 * blast all fasta sequences against the ncbi database. The output is html formated, to get it legible for people.
 */
    shell:
    '''
    #!/bin/sh
    contig=`grep ">" !{uniq_seqHtml} | cut -d" " -f1 | cut -c 2-`
    !{params.blastp} -db !{ncbiDB} -query "!{uniq_seqHtml}" -html -out "!{outputDir}/$contig.html" -num_threads !{params.blast_cpu} 
    '''

}

if(params.gff && params.contigs) {
    twoBitDir = outputDir
    indexFile = outputDir + "/index"
    chromFile = outputDir + "/chrom.sizes"
    gffFile = file(params.gff)
    gffInput = Channel.from(gffFile)
    gffContigFiles = Channel.create()
    contigsFile = file(params.contigs)
    assembly = Channel.create()

    Channel.fromPath(contigsFile)
         .splitFasta(file: "fa", by:50)
         .into(assembly)

    process faToTwoBit {

        cpus 2

        memory '1 GB'

        input:
        val assemblyChunk from assembly

        output:
        file "/${twoBitDir}/${assemblyChunk.getName()}" into twoBits

        shell:
        '''
        #!/bin/sh
        !{params.faToTwoBit} '!{assemblyChunk}' '!{twoBitDir}/!{assemblyChunk.getName()}'
        '''
    }

    process prepareViewFiles {

       cpus 1

       memory '4 GB'

       input:
       val gffFile from gffInput

       output:
       file 'gff/*' into gffContigFiles mode flatten
       file "/${indexFile}" into index

       script:
       """
       #!/bin/sh
       mkdir gff
       $PYTHON ${baseDir}/scripts/view_index.py --faa ${genomeFaa} --contigs ${contigsFile} --gff ${gffFile} --gffdir gff --out ${indexFile}
       """
    }


    process faSizes {

       cpus 1

       memory '4 GB'

       input:
       file contigsFile

       output:
       file "/${chromFile}" into chromSizes

       script:
       """
       #!/bin/sh
       $PYTHON ${baseDir}/scripts/fa_sizes.py --fa ${contigsFile} --out ${chromFile}
       """
    }

    process gffToBed {

       cpus 1

       memory '4 GB'

       validExitStatus 0,255

       input:
       file gffFile from gffContigFiles
       file chromSizes

       script:
       """
       #!/bin/sh
       $PYTHON ${baseDir}/scripts/gff2bed.py --gff "${gffFile}" --bed "${outputDir}/${gffFile.baseName}.bed"
       ${params.bedToBigBed} "${outputDir}/${gffFile.baseName}.bed" ${chromSizes} "${outputDir}/${gffFile.baseName}.bb"
       """
    }
    twoBits.collectFile();
}

coverageFiles = Channel.create()
if(params.bam){
    coverages = Channel.create()
    sortedIndexedBam = Channel.from(params.bam.split(',').collect{file(it)})
    process bamToCoverage {

       cpus 2

       memory '4 GB'

       input:
       val bam from sortedIndexedBam

       output:
       file "${bam.baseName}" into coverages

       when:
       bam != ''

       script:
       """
       #!/bin/sh
       $PYTHON ${baseDir}/scripts/bam_to_coverage.py ${bam} > ${bam.baseName}
       """
    }
    coverages.collectFile().toList().into(coverageFiles)
} else {
    coverageFiles.bind([])
}

uniq_overview = uniq_overview.collectFile()

process createOverview {

   cpus 2

   memory '16 GB'

   input:
   file blast_all
   file uniq_overview
   val coverageFiles

   output:
   val outputDir + '/overview.txt' into over

   shell:
   '''
   #!/bin/sh
   searchParam=""
   if [ -n !{params.search} ]
   then
       searchParam="--search=!{searchFile}"
   fi

   coverageParam=""
   if [ -n !{coverageFiles} ]
   then
       coverageParam=" -c !{coverageFiles.join(' ')} "
   fi
   !{PYTHON} !{baseDir}/scripts/create_overview.py -u !{uniq_overview}  -faa "!{outputDir}/txt_faa_files/" -o !{outputDir}  ${searchParam} ${coverageParam}
   '''
}
