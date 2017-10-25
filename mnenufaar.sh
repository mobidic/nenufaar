#!/usr/bin/sh

###########################################################################
#########							###########
#########		Meta nenufaar				###########
######### @uthor : D Baux	david.baux<at>inserm.fr		###########
######### Date : 12/05/2016					###########
#########							###########
###########################################################################


VERSION=0.1.1
USAGE="
Program: mnenufaar
Version: ${VERSION}
Contact: Baux David <david.baux<at>inserm.fr>

Usage: $(basename "$0") [options] -- program to perform an nenufaar analyses of families: merge BAMs and call variants on merged BAM. Single VCF output for all samples.

Example:
sh mnenufaar.sh -i=path/to/run/folder/

Arguments:

    -i,  --input_path    set the absolute path to input directory (must be created before script execution)
Options:
    -h,  --help    shows this help text
    -c, --caller			Chooses which GATK variant caller to use: ug: UnifiedGenotyper or hc, HaplotypeCaller default hc
    -up, --use_platypus			true, false Platypus variant calling - Default behaviour is GATK variant calling, then Platypus and VCF merging using GATK CombineVariants
    -dcov, --downsample_to_coverage	GATK option default 1000 - selects the variant caller, HaplotypeCaller if dcov <= 1000, or UnifiedGenotyper - DEPRECATED IN THIS VERSION
    -a, --annotator			Name of annotator: cava (output to textfile), annovar (output to both text and vcf file), vep, snpeff (both output to VCF), or merge to generate a merged cava/annovar file (hg19), default no annotation
    -f, --filter			combined with annovar only, filters out variants with MAF > 1% in ExAC, ESP or 1KG, true/false, default false. Warning: does not produce the annotated VCF, only tab delimited file.
    -g, --genome			Version of genome (assembly), either hg19 or hg38, default hg19
    -p, --protocol			Protocol used to select sequences: capture/amplicon/wgs, default capture
    -o,  --output_path			Sets the absolute path to output directory (must be created before script execution)
    -r,  --reference			Path to genome fasta reference file
    -snp, --snp  			Sets the absolute path to vcf file for dbSNP
    -indel1, --indel1			Sets the absolute path to vcf file for indels reference (1000G_phase1.indels sor Mills_and_1000G_gold_standard)
    -indel2, --indel2			Sets the absolute path to vcf file for indels reference (1000G_phase1.indels or Mills_and_1000G_gold_standard)S
    -hsm, --hsmetrics			Boolean true,false: Asks for Picard HsMetrics calculation: necessitates a Picard.intervals.list (target picard file) file at the root of the run folder, default false - can also take a baits interval file named Picard.baits.intervals.list
    -l, --gene_list path to a txt file with a #NAME and a list of genes to be marked in a annovar file


 Docs:

 	http://bio-bwa.sourceforge.net/bwa.shtml
	http://www.htslib.org/doc/samtools-1.2.html
 	http://broadinstitute.github.io/picard/command-line-overview.html
 	https://www.broadinstitute.org/gatk/guide/best-practices?bpm=DNAseq
	https://www.broadinstitute.org/gatk/guide/tooldocs/org_broadinstitute_gatk_engine_CommandLineGATK.php#--downsample_to_coverage
	http://www.well.ox.ac.uk/cava
	http://annovar.openbioinformatics.org/en/latest/
	https://github.com/lindenb/jvarkit

#	<my run folder>
#		|
#		<Intervals.list>
#		|
#		<Picard.intervals.list> #optionnal, mandatory if -hsm=true
#		|
#		<sample_1>
#		|	|
#		|	|
#		|	<sample_1.R1.fastq.gz>
#		|	|
#		|	<sample_1.R2.fastq.gz>
#		|	|
#		|
#		<sample_2>
#		|	|
#		|	|
#		|	<sample_2.R1.fastq.gz>
#		|	|
#		|	<sample_2.R2.fastq.gz>
#		|
#		|
#		<etc> ....



 "


##############		If no options are given, print help message	#################################

if [ $# -eq 0 ]; then
	echo "${USAGE}"
	echo "Error Message : No arguments provided"
	echo ""
	exit 1
fi

###############		Get options from conf file			#################################

CONFIG_FILE=mnenufaar.conf

#we check params against regexp

UNKNOWN=`cat ${CONFIG_FILE} | grep -Evi "^(#.*|[A-Z0-9_]*=[a-z0-9_ \.\/\$\{\}\(\)\"\'=-]*)$"`
if [ -n "${UNKNOWN}" ]; then
	echo "Error in config file. Not allowed lines:"
	echo ${UNKNOWN}
	exit 1
fi

source ./${CONFIG_FILE}



###############		Get arguments from command line			#################################

while [[ "$#" -gt 0 ]]
do
KEY="$1"
case "${KEY}" in
	-i|--input)					#mandatory
	INPUT_PATH="$2"
	shift
	;;
	-o|--output)
	OUTPUT_PATH="$2"
	shift
	;;
	-r|--reference)
	REF_PATH="$2"
	shift
	;;
	-snp|--snp)
	SNP_PATH="$2"
	shift
	;;
	-indel1|--indel1)
	INDEL1="$2"
	shift
	;;
	-indel2|--indel2)
	INDEL2="$2"
	shift
	;;
	-dcov|--downsample_to_coverage)
	DCOV="$2"
	shift
	;;
	-g|--genome)				#default hg19
	GENOME="$2"
	shift
	;;
	-c|--caller)				#default HC
	CALLER="$2"
	shift
	;;
	-p|--protocol)				#default capture
	PROTOCOL="$2"
	shift
	;;
	-hsm|--hsmetrics)			#default false
	HSMETRICS="$2"
	shift
	;;
	-a|--annotator)
	ANNOTATOR="$2"
	shift
	;;
	-f|--filter)				#default false
	FILTER="$2"
	shift
	;;
	-up|--use_platypus)			#default true
	USE_PLATYPUS="$2"
	shift
	;;
	-h|--help)
	echo "${USAGE}"
	exit 1
	;;
	-l|--gene_list)
	LIST="$2"
	shift
	;;
	-cu|--clean_up)					#default true
	CLEAN_UP="$2"
	shift
	;;
	-log|--log-file)
	LOG_FILE="$2"
	shift
	;;
	*)
	echo "Error Message : Unknown option ${KEY}" 	# unknown option
	exit
	;;
esac
shift
done

mkdir ${OUTPUT_PATH}
if [ ${#LOG_FILE} -eq 0 ];then
	LOG_FILE="${OUTPUT_PATH}mnenufaar_${ID}.log"
fi




echo ""
echo "#############################################################################################"
echo "mnenufaar ${VERSION} will be launched. tail -f ${LOG_FILE} for detailed information.   "
echo "#############################################################################################"

touch ${LOG_FILE}
exec &>${LOG_FILE}


echo ""
echo "#############################################################################################"
echo "Config File ${CONFIG_FILE} successfully loaded - `date`"
echo "##############################################################################################"

########	add / to INPUT_PATH if needed
if [[ "${INPUT_PATH}" =~ .+[^\/]$ ]];then
	INPUT_PATH="${INPUT_PATH}/"
fi


########	change assembly if necessary				########

if [[ "${GENOME}" == 'hg38' ]]; then
	REF_PATH='refData/genome/hg38/hg38.fa'
	SNP_PATH='refData/dbSNP/144_hg38/dbsnp_144.hg38.vcf.gz'
	INDEL1='refData/indelReference/hg38/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz'
	INDEL2='refData/indelReference/hg38/Homo_sapiens_assembly38.known_indels.vcf.gz'
fi

validate_genome() { echo "hg19 hg38" | grep -F -q -w "$1"; }
if [ "${GENOME}" != 0 ]; then
	validate_genome "${GENOME}" && echo "VALID GENOME OPTION = ${GENOME}" || { echo "INVALID GENOME OPTION = ${GENOME} -> see help (-h)" && exit 1; }
fi

if [ "${LIST}" != '' ] && [ ! -e "${LIST}" ]; then
	echo 'GENE LIST FILE ${LIST} DOES NOT EXIST -> see help (-h)' && exit 1;
fi

if [ "${LIST}" != '' ]; then
	LIST="-l ${LIST}"
fi

DATE1=$(date +"%s")

##########################################################################
################## Functions Declaration 			#######################
###########################################################################
#https://wikis.utexas.edu/display/bioiteam/Example+BWA+alignment+script
# general function that exits after printing its text argument
#   in a standard format which can be easily grep'd.
err() {
	echo "[$(basename "$0")]...The script has terminated unexpectedly $1";
	echo "[$(basename "$0")]...The script has terminated unexpectedly $1";
	exit 1 # any non-0 exit code signals an error
}
# function to check return code of programs.
# exits with standard message if code is non-zero;
# otherwise displays completiong message and date.
#   arg 1 is the return code (usually $?)
#   arg2 is text describing what ran
ckRes() {
	if [ "$1" == '0' ]; then
		echo "[$(basename "$0")]...Done - $2 - `date`";
	else
		err "[$(basename "$0")]...$2 returned non-0 exit code $1";
	fi
}
# function that checks if a file exists
#   arg 1 is the file name
#   arg2 is text describing the file (optional)
ckFile() {
	if [ ! -e "$1" ]; then
		err "[$(basename "$0")]...$2 File '$1' not found";
	fi
}
# function that checks if a file exists and
#   that it has non-0 length. needed because
#   programs don't always return non-0 return
#   codes, and worse, they also create their
#   output file with 0 length so that just
#   checking for its existence is not enough
#   to ensure the program ran properly
ckFileSz() {
	ckFile $1 $2;
	SZ=$(ls -l $1 | awk '{print $5}');
	if [ "$SZ" == '0' ]; then
		err "[$(basename "$0")]...$2 File '$1' is zero length";
	fi
}
###########################################################################
###########################################################################
###########################################################################

###
###nenufaar generate BAM for each sample
###


echo "COMMAND: nohup ${SHELL} ${NENUFAAR} -i ${INPUT_PATH} -o ${OUTPUT_PATH} -r ${REF_PATH} -snp ${SNP_PATH} -indel1 ${INDEL1} -indel2 ${INDEL2} -g ${GENOME} -dcov ${DCOV} -c ${CALLER} -p ${PROTOCOL} -hsm ${HSMETRICS} -id ${ID} -b "

nohup ${SHELL} ${NENUFAAR} -i ${INPUT_PATH} -o ${OUTPUT_PATH} -r ${REF_PATH} -snp ${SNP_PATH} -indel1 ${INDEL1} -indel2 ${INDEL2} -g ${GENOME} -dcov ${DCOV} -c ${CALLER} -p ${PROTOCOL} -hsm ${HSMETRICS} -id ${ID} -b

#I often have an error wifth a fi at the end of nenufaar script, so commented until fixed
STATUS=$?
if [ "${STATUS}" -ne 0 ];then
	echo "###########################################################################"
	echo "There has been an issue with BAM generation - check log files - mnenufaar will exit"
	echo "###########################################################################"
	exit 1
fi
###
###merge all BAMs - first move them in a common directory
###

RUN_BASEDIR_NAME=$(basename "${INPUT_PATH}")
BAMS_PARENT_DIR=${OUTPUT_PATH}${RUN_BASEDIR_NAME};


BAMS_DIR=$(find ${BAMS_PARENT_DIR} -mindepth 1 -maxdepth 1 -type d)

mkdir -p ${OUTPUT_PATH}${RUN_BASEDIR_NAME}/MERGED_SAMPLES
MERGED_DIR=${OUTPUT_PATH}${RUN_BASEDIR_NAME}/MERGED_SAMPLES/

for CURRENT_BAM_DIR in ${BAMS_DIR[@]}
do
	mv ${CURRENT_BAM_DIR}/${ID}/*.ba* ${MERGED_DIR}
done

BAMS_FILES=(${MERGED_DIR}*.bam)
BAIS_FILES=(${MERGED_DIR}*.bai)

echo "#############################################################################################"
echo "SAMBAMBA : merge - `date` ID_ANALYSE : ${ID} - Run : ${RUN_BASEDIR_NAME} - SAMPLES : ${BAMS_FILES[@]}"
echo "#############################################################################################"

echo "COMMAND: ${SRUN_24_COMMAND} ${SAMBAMBA} merge -t ${NB_THREAD} ${MERGED_DIR}MERGED_SAMPLES.bam ${BAMS_FILES[@]}"

${SRUN_24_COMMAND} ${SAMBAMBA} merge -t ${NB_THREAD} ${MERGED_DIR}MERGED_SAMPLES.bam ${BAMS_FILES[@]}

STATUS=$?
if [ "${STATUS}" -ne 0 ];then
	echo "###########################################################################"
	echo "There has been an issue with BAM merging - check log files - mnenufaar will exit"
	echo "###########################################################################"
	exit 1
fi



rm ${BAMS_FILES[@]}
rm ${BAIS_FILES[@]}



###
###nenufaar generate single VCF for all samples
###

echo "COMMAND: nohup ${SHELL} nenufaar.sh -i ${INPUT_PATH} -o ${OUTPUT_PATH} -r ${REF_PATH} -snp ${SNP_PATH} -indel1 ${INDEL1} -indel2 ${INDEL2} -g ${GENOME} -dcov ${DCOV} -c ${CALLER} -p ${PROTOCOL} -hsm ${HSMETRICS} -a ${ANNOTATOR} -f ${FILTER} -up ${USE_PLATYPUS} ${LIST} -vc"

nohup ${SHELL} ${NENUFAAR} -i ${INPUT_PATH} -o ${OUTPUT_PATH} -r ${REF_PATH} -snp ${SNP_PATH} -indel1 ${INDEL1} -indel2 ${INDEL2} -g ${GENOME} -dcov ${DCOV} -c ${CALLER} -p ${PROTOCOL} -hsm ${HSMETRICS} -a ${ANNOTATOR} -f ${FILTER} -up ${USE_PLATYPUS} ${LIST} -vc

STATUS=$?
if [ "${STATUS}" -ne '0' ];then
	echo "###########################################################################"
	echo "There has been an issue with VCF generation - check log files - mnenufaar will exit"
	echo "###########################################################################"
	exit 1
fi

DATE2=$(date +"%s")
DIFF=$((${DATE2}-${DATE1}))

echo "#############################################################################################"
echo "#############################################################################################"
echo "META NENUFAAR MULTI-SAMPLE RUN: ${ID} COMPLETED WITH SUCCESS"
echo "EXECUTION TIME:"
printf '%dh:%dm:%ds\n' $((${DIFF}/3600)) $((${DIFF}%3600/60)) $((${DIFF}%60))
echo "#############################################################################################"
echo "#############################################################################################"

exit 0
