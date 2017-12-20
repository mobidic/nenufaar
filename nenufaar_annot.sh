#!/usr/bin/bash

###########################################################################
#########							###########
#########		VCF Annotation script			###########
######### @uthor : D Baux	david.baux<at>inserm.fr		###########
######### Date : 06/07/2016					###########
#########							###########
###########################################################################


VERSION=1.6.1
USAGE="
Program: nenufaar_annot
Version: ${VERSION}
Contact: Baux David <david.baux<at>inserm.fr>

Usage: $(basename "$0") [options] -- program to annotate VCF files...

Example:
bash nenufaar_annot_${VERSION}.sh -a=cava

Important:
LAUNCH WITH BASH!!! NOT SH

Options:
	-h,	--help    	show this help text
	-a,	--annotator	Name of annotator: cava (output to textfile), annovar (output to both text and vcf file), vep and snpeff (both output to VCF), or merge to generate a merged cava/annovar file
	-g, 	--genome	Version of genome (assembly), either hg19 or hg38, default hg19 (currently hg38 only with annovar)
	-i,	--input_path    set the absolute path to input directory (must be created before script execution)(default /Users/galaxy_dev_user/variant-calling-pipeline-dev/annot_input/)
	-o,	--output_path   set the absolute path to output directory (must be created before script execution)(default /Users/galaxy_dev_user/variant-calling-pipeline-dev/annot_output/)
	-f,	--filter	combined with annovar only, filters out variants with MAF > 1% in ExAC, ESP or 1KG, true/false, default false. Warning: does not produce the annotated VCF, only tab delimited file
	-m,	--multi_sample	for annovar, true, false, will add '-allsample -withfreq' args in convert2annovar.pl script if true
	-l,	--gene_list	path to a txt file with a #NAME and a list of genes to be marked in a annovar file
	-cu,	--clean_up	Boolean true, false: set to false to keep intermediate files (for dev purpose)

Directories Arborescence:

#	<input_folder>
#		|
#
#		|
#		<sample_1.vcf>
#		|
#		|
#		|
#		<sample_2.vcf>
#		|
#		|
#		|
#		<etc> ....

Docs:

	http://www.well.ox.ac.uk/cava
	http://annovar.openbioinformatics.org/en/latest/

 "


##############		If no options are given, print help message	#################################

if [ "$#" -eq 0 ]; then
	echo "${USAGE}"
	echo "Error Message : No arguments provided"
	echo ""
	exit 1
fi

###############		Get options from conf file			#################################

CONFIG_FILE=nenufaar_annot.conf

#we check params against regexp

UNKNOWN=`cat ${CONFIG_FILE} | grep -Evi "^(#.*|[A-Z0-9_]*=[a-z0-9_ \.\/\$\{\}\(\)\"\'=-]*)$"`
if [ -n "${UNKNOWN}" ]; then
	echo "Error in config file. Not allowed lines:"
	echo "${UNKNOWN}"
	exit 1
fi

source ./${CONFIG_FILE}

echo ""
echo "#############################################################################################"
echo "Config File ${CONFIG_FILE} successfully loaded - `date`"
echo "##############################################################################################"

###############		Get arguments from command line			#################################


while [[ "$#" -gt 0 ]]
do
KEY="$1"
case "${KEY}" in
	-h|--help)
	echo "${USAGE}"
	exit 1
	;;
	-i|--input)
	INPUT_PATH="$2"
	shift
	;;
	-o|--output)
	OUTPUT_PATH="$2"
	shift
	;;
	-a|--annotator)
	ANNOTATOR="$2"
	shift
	;;
	-g|--genome)
	GENOME="$2"
	shift
	;;
	-f|--filter)
	FILTER="$2"
	shift
	;;
	-m|--multi_sample)
	MULTISAMPLE="$2"
	shift
	;;
	-l|--gene_list)
	LIST="$2"
	shift
	;;
	-cu|--clean_up)
	CLEAN_UP="$2"
	shift
	;;
	-log|--log-file)
	LOG_FILE="$2"
	shift
	;;
	*)
	echo "Error Message : Unknown option $i" # unknown option
	exit
	;;
esac
shift
done
#########	Test mandatory arguments setting  #########

if [[ "${INPUT_PATH}" =~ .+[^\/]$ ]];then
	INPUT_PATH="${INPUT_PATH}/"
fi

if [ -z "${OUTPUT_PATH}" ];then
	mkdir ${INPUT_PATH}annotated
	OUTPUT_PATH=${INPUT_PATH}annotated
fi

if [[ "${OUTPUT_PATH}" =~ .+[^\/]$ ]];then
	OUTPUT_PATH="${OUTPUT_PATH}/"
fi

if [ -z "${INPUT_PATH}" ] || [ -z "${ANNOTATOR}" ] || [ -z "${GENOME}" ]; then
	echo "Error Message : Mandatory argument missing -> see help (-h)"
	exit 1
fi

validate_annotator() { echo "cava annovar merge" | grep -F -q -w "$1"; }
if [ "${ANNOTATOR}" != 0 ]; then
	validate_annotator "${ANNOTATOR}" && echo "VALID ANNOTATOR OPTION = ${ANNOTATOR}" || { echo "INVALID ANNOTATOR OPTION = ${ANNOTATOR} -> see help (-h)" && exit 1; }
fi

validate_genome() { echo "hg19 hg38" | grep -F -q -w "$1"; }
if [ "${GENOME}" != 0 ]; then
	validate_genome "${GENOME}" && echo "VALID GENOME OPTION = ${GENOME}" || { echo "INVALID GENOME OPTION = ${GENOME} -> see help (-h)" && exit 1; }
fi

validate_boolean() { echo "true false" | grep -F -q -w "$1"; }
validate_boolean "${CLEAN_UP}" && echo "VALID CLEAN_UP OPTION = ${CLEAN_UP}" || { echo "INVALID CLEAN_UP OPTION = ${CLEAN_UP} - EXITING" && exit 1; }

if [ "${GENOME}" == 'hg38' ] && [ "${ANNOTATOR}" != 'annovar' ]; then
	echo "INVALID GENOME/ANNOTATOR COMBINATION -> see help (-h)" && exit 1
fi

if [ "${ANNOTATOR}" != 'annovar' ] && [ "${FILTER}" != 'false' ]; then
	echo "INVALID ANNOTATOR/FILTER COMBINATION -> see help (-h)" && exit 1
fi

if [ "${ANNOTATOR}" == 'cava' ] && [ "${LIST}" != '' ]; then
	#echo "INVALID ANNOTATOR/LIST COMBINATION -> see help (-h)" && exit 1
	LIST=''
fi

if [ "${GENOME}" == 'hg19' ];then
	SPIDEX=",spidex"
	SPIDEX_OP=",f"
	SPIDEX_COMMA=","
	POP_FREQ_MAX=",popfreq_max_20150413"
	POP_FREQ_MAX_OP=",f"
	POP_FREQ_MAX_COMMA=","
elif [ "${GENOME}" == 'hg38' ];then
	REF_PATH=refData/genome/hg38/hg38.fa
fi
if [ "${MULTISAMPLE}" == 'true' ];then
	SAMPLE_ARG='-allsample -withfreq'
fi

if [ ${#LOG_FILE} -ne 0 ];then
	touch ${LOG_FILE}
	exec &>${LOG_FILE}
fi

echo "nenufaar annotation module ${VERSION}"
echo "ANNOTATOR : ${ANNOTATOR}"
echo "GENOME : ${GENOME}"
echo "FILTER : ${FILTER}"
echo "MULTISAMPLE : ${MULTISAMPLE}"
echo "CFTR : ${CFTR}"
echo "GENEMAPR : ${GENEMAPR}"
echo "KEGG : ${KEGG}"
echo "CAVA_VERSION : ${CAVA_VERSION}"
echo "ANNOVAR_VERSION : ${ANNOVAR_VERSION}"
echo "TABIX_VERSION : ${TABIX_VERSION}"
echo "IURC_MERGE_VERSION : ${IURC_MERGE_VERSION}"
echo "ADD_BARCODE_VERSION : ${ADD_BARCODE_VERSION}"
echo "IURC_MARK_GENES_VERSION : ${IURC_MARK_GENES_VERSION}"
echo "BCFTOOLS : ${BCFTOOLS}"
echo "ADD_LED_VERSION : ${ADD_LED_VERSION}"

echo "Your analyze ID is : ${ID}"

echo "INPUT ABSOLUTE PATH  = ${INPUT_PATH}"
echo "OUTPUT ABSOLUTE PATH = ${OUTPUT_PATH}"

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
	if [ "$1" == "0" ];then
		echo "[$(basename "$0")]...Done - $2 - `date`"
	else
		err "[$(basename "$0")]...$2 returned non-0 exit code $1"
	fi
}
# function that checks if a file exists
#   arg 1 is the file name
#   arg2 is text describing the file (optional)
ckFile() {
	if [ ! -e "$1" ];then
		err "[$(basename "$0")]...$2 File '$1' not found"
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
	SZ=`ls -l $1 | awk '{print $5}'`
	if [ "$SZ" == "0" ];then
		err "[$(basename "$0")]...$2 File '$1' is zero length"
	fi
}
###########################################################################
###########################################################################
###########################################################################

SUFFIX=''

SAMPLES_FILE_LIST=(${INPUT_PATH}*.vcf)
echo "SAMPLES_FILE_LIST : ${SAMPLES_FILE_LIST[@]}"

## Génération des jobs nécessaires à l'analyse.
for SAMPLE_FILE_PATH in  ${SAMPLES_FILE_LIST[@]}
do
	SAMPLE_FILE=$(basename "${SAMPLE_FILE_PATH}")
	echo "CURRENT SAMPLE FILE: ${SAMPLE_FILE}"
	ckFileSz ${INPUT_PATH}${SAMPLE_FILE}
	# ANNOTATION
	if [ "${ANNOTATOR}" != 0 ]; then
		#if [ "${ANNOTATOR}" == 'annovar' ] || [ "${ANNOTATOR}" == 'merge' ]; then
		if [ "${ANNOTATOR}" == 'annovar' ] && [ "${MULTISAMPLE}" == 'false' ]; then
			echo "#############################################################################################"
			echo "BCFTOOLS : pre-processing of VCF - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${BCFTOOLS} norm -m-both ${INPUT_PATH}${SAMPLE_FILE} | ${BCFTOOLS} norm -f ${REF_PATH} -o ${INPUT_PATH}${SAMPLE_FILE}.norm.vcf"
			echo "#############################################################################################"
			#we pre-process vcf for annovar (split multi-alleles and left normalisation of indels)
			#http://annovar.openbioinformatics.org/en/latest/articles/VCF/
			
			${SRUN_SIMPLE_COMMAND} ${BCFTOOLS} norm -m-both ${INPUT_PATH}${SAMPLE_FILE} | ${BCFTOOLS} norm -f ${REF_PATH} -o ${OUTPUT_PATH}${SAMPLE_FILE}.norm.vcf
			ckRes $? "BCFTOOLS : pre-processing of VCF "
			ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.norm.vcf
			VCF=${OUTPUT_PATH}${SAMPLE_FILE}.norm.vcf
		elif [ "${MULTISAMPLE}" == 'true' ];then
			VCF=${INPUT_PATH}${SAMPLE_FILE}
		fi
			
		case ${ANNOTATOR} in
		"cava")
			echo "#############################################################################################"
			echo "CAVA : VCF Clinical Annotation of VAriants - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_24_COMMAND} ${PYTHON} ${CAVA} -c ${CAVA_DIR}config.txt -i ${INPUT_PATH}${SAMPLE_FILE} -o ${OUTPUT_PATH}${SAMPLE_FILE}.cava"
			echo "#############################################################################################"

			${SRUN_24_COMMAND} ${PYTHON} ${CAVA} -c ${CAVA_DIR}config.txt -i ${INPUT_PATH}${SAMPLE_FILE} -o ${OUTPUT_PATH}${SAMPLE_FILE}.cava

			ckRes $? "CAVA : Clinical Annotation of VAriants "
			ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt
			TXT_FILE=${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt
		;;
		"annovar")
			if [ "${FILTER}" == 'true' ];then
				SUFFIX='filtered'
				echo "#############################################################################################"
				echo "ANNOVAR : Prepare avinput - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} ${ANNOVAR}convert2annovar.pl -format vcf4 ${SAMPLE_ARG} -includeinfo ${INPUT_PATH}${SAMPLE_FILE} -outfile ${INPUT_PATH}${SAMPLE_FILE}.avinput"
				echo "#############################################################################################"

				${SRUN_SIMPLE_COMMAND} ${PERL} ${ANNOVAR}convert2annovar.pl -format vcf4 ${SAMPLE_ARG} -includeinfo ${VCF} -outfile ${OUTPUT_PATH}${SAMPLE_FILE}.avinput

				ckRes $? "ANNOVAR : Prepare avinput"
				ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.avinput
				
				echo "#############################################################################################"
				echo "ANNOVAR : filter gnomeAD exome MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype gnomad_exome -score_threshold 0.01 -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE} ${OUTPUT_PATH}${SAMPLE_FILE}.avinput ${ANNOVAR_HUMAN_DB}"
				echo "#############################################################################################"

				${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype gnomad_exome -score_threshold 0.01 -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE} ${OUTPUT_PATH}${SAMPLE_FILE}.avinput ${ANNOVAR_HUMAN_DB}
				ckRes $? "ANNOVAR : filter gnomeAD exome MAF > 0.01"
				ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_exome_filtered
				
				echo "#############################################################################################"
				echo "ANNOVAR : filter gnomeAD genome MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype gnomad_genome -score_threshold 0.01 -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE} ${OUTPUT_PATH}${SAMPLE_FILE}.avinput ${ANNOVAR_HUMAN_DB}"
				echo "#############################################################################################"

				${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype gnomad_genome -score_threshold 0.01 -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE} ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_exome_filtered ${ANNOVAR_HUMAN_DB}
				ckRes $? "ANNOVAR : filter gnomeAD genome MAF > 0.01"
				ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_genome_filtered

				#echo "#############################################################################################"
				#echo "ANNOVAR : filter 1000G MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				#echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype 1000g2015aug_all -maf 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.avinput ${ANNOVAR_HUMAN_DB}"
				#echo "#############################################################################################"
				#
				#${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype 1000g2015aug_all -maf 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.avinput ${ANNOVAR_HUMAN_DB}
				#ckRes $? "ANNOVAR : filter 1000G MAF > 0.01"
				#ckFileSz ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_ALL.sites.2015_08_filtered
				#
				#echo "#############################################################################################"
				#echo "ANNOVAR : filter kaviar MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				#echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype kaviar_20150923 -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_ALL.sites.2015_08_filtered ${ANNOVAR_HUMAN_DB}"
				#echo "#############################################################################################"
				#
				#${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype kaviar_20150923 -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_ALL.sites.2015_08_filtered ${ANNOVAR_HUMAN_DB}
				#ckRes $? "ANNOVAR : filter ExAC MAF > 0.01"
				#ckFileSz ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_kaviar_20150923_filtered
				#
				#echo "#############################################################################################"
				#echo "ANNOVAR : filter ExAC MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				#echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype exac03 -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_kaviar_20150923_filtered ${ANNOVAR_HUMAN_DB}"
				#echo "#############################################################################################"
				#
				#${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype exac03 -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_kaviar_20150923_filtered ${ANNOVAR_HUMAN_DB}
				#ckRes $? "ANNOVAR : filter ExAC MAF > 0.01"
				#ckFileSz ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_exac03_filtered
				#
				#echo "#############################################################################################"
				#echo "ANNOVAR : filter ESP6500 MAF > 0.01 - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				#echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype esp6500siv2_all -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_exac03_filtered ${ANNOVAR_HUMAN_DB}"
				#echo "#############################################################################################"
				#
				#${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}annotate_variation.pl -thread ${NB_THREAD} -filter -dbtype esp6500siv2_all -score_threshold 0.01 -buildver ${GENOME} -out ${INPUT_PATH}${SAMPLE_FILE} ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_exac03_filtered ${ANNOVAR_HUMAN_DB}
				#ckRes $? "ANNOVAR : filter ESP6500 MAF > 0.01"
				#ckFileSz ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_esp6500siv2_all_filtered

				echo "#############################################################################################"
				echo "ANNOVAR : Functional Annotation of Variants - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_genome_filtered ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -arg '-splicing 100',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA} -otherinfo"
				echo "#############################################################################################"

				${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_genome_filtered ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -arg '-splicing 100',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA} -otherinfo

				ckRes $? "ANNOVAR : Functional Annotation of Variants"
				ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.${GENOME}_multianno.txt
				TXT_FILE=${OUTPUT_PATH}${SAMPLE_FILE}.annovar.${GENOME}_multianno.txt
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_exome_filtered
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_genome_filtered
				#rm ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_exac03_filtered
				#rm ${INPUT_PATH}${SAMPLE_FILE}.${GENOME}_esp6500siv2_all_filtered
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.avinput
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.log
				mkdir ${OUTPUT_PATH}annovar_dropped
				#mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_ALL.sites.2015_08_dropped ${OUTPUT_PATH}annovar_dropped
				#mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_kaviar_20150923_dropped ${OUTPUT_PATH}annovar_dropped
				#mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_exac03_dropped ${OUTPUT_PATH}annovar_dropped
				#mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_esp6500siv2_all_dropped ${OUTPUT_PATH}annovar_dropped
				mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_exome_dropped ${OUTPUT_PATH}annovar_dropped
				mv ${OUTPUT_PATH}${SAMPLE_FILE}.${GENOME}_gnomad_genome_dropped ${OUTPUT_PATH}annovar_dropped
			else
				echo "#############################################################################################"
				echo "ANNOVAR : Functional Annotation of Variants - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
				#echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${INPUT_PATH}${SAMPLE_FILE} ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147,dbnsfp31a_interpro${POP_FREQ_MAX},clinvar_20170130,kaviar_20150923,esp6500siv2_all,exac03,1000g2015aug_all,dbnsfp33a,mcap,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 50',,,,,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}"
				echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${INPUT_PATH}${SAMPLE_FILE} ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 50',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}"
				echo "#############################################################################################"

				#${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${INPUT_PATH}${SAMPLE_FILE} ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147,dbnsfp31a_interpro${POP_FREQ_MAX},clinvar_20170130,kaviar_20150923,esp6500siv2_all,exac03,1000g2015aug_all,dbnsfp33a,mcap,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 50',,,,,,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}
				${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${VCF} ${ANNOVAR_HUMAN_DB} -buildver ${GENOME} -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 50',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}

				ckRes $? "ANNOVAR : Functional Annotation of Variants"
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.avinput
				ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.${GENOME}_multianno.txt
				TXT_FILE=${OUTPUT_PATH}${SAMPLE_FILE}.annovar.${GENOME}_multianno.txt
			fi
		;;
		"merge")
			SUFFIX='HGVS'
			echo "#############################################################################################"
			echo "CAVA : VCF Clinical Annotation of VAriants - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_24_COMMAND} ${PYTHON} ${CAVA} -c ${CAVA_DIR}config.txt -i ${INPUT_PATH}${SAMPLE_FILE} -o ${OUTPUT_PATH}${SAMPLE_FILE}.cava"
			echo "#############################################################################################"

			${SRUN_24_COMMAND} ${PYTHON} ${CAVA} -c ${CAVA_DIR}config.txt -i ${INPUT_PATH}${SAMPLE_FILE} -o ${OUTPUT_PATH}${SAMPLE_FILE}.cava

			ckRes $? "CAVA : Clinical Annotation of VAriants "
			ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt
			#TXT_FILE=${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt

			echo "#############################################################################################"
			echo "ANNOVAR : Functional Annotation of Variants - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${INPUT_PATH}${SAMPLE_FILE} ${ANNOVAR_HUMAN_DB} -buildver hg19 -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 100',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}"
			echo "#############################################################################################"

			${SRUN_24_COMMAND} ${PERL} ${ANNOVAR}table_annovar.pl -thread ${NB_THREAD} ${INPUT_PATH}${SAMPLE_FILE} ${ANNOVAR_HUMAN_DB} -buildver hg19 -out ${OUTPUT_PATH}${SAMPLE_FILE}.annovar -remove -protocol refGene,avsnp147${POP_FREQ_MAX},clinvar_20170130,gnomad_exome,gnomad_genome,dbnsfp33a,dbscsnv11${SPIDEX} -operation g,f,f,f,f,f,f${POP_FREQ_MAX_OP}${SPIDEX_OP} -nastring . -vcfinput -arg '-splicing 100',,,,,,${POP_FREQ_MAX_COMMA}${SPIDEX_COMMA}

			rm ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.avinput
			ckRes $? "ANNOVAR : Functional Annotation of Variants"
			ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.txt
			echo "#############################################################################################"
			echo "MERGING CAVA & ANNOVAR annotation files : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} -wT ${IURC_MERGE} -c ${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt -a ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.txt"
			echo "#############################################################################################"

			${SRUN_SIMPLE_COMMAND} ${PERL} -wT ${IURC_MERGE} -c ${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt -a ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.txt

			ckRes $? "MERGED Cava & Annovar"
			ckFileSz ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.cava.merged.txt
			TXT_FILE=${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.cava.merged.txt
			if [ "${CLEAN_UP}" == 'true' ];then
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.annovar.hg19_multianno.txt
				rm ${OUTPUT_PATH}${SAMPLE_FILE}.cava.txt
			fi
		esac
	fi
	if [ "${ANNOTATOR}" == 'cava' ]; then
		echo "#############################################################################################"
		echo "PERL : Add spidex - `date` ID_ANALYSE : ${ID}  - SAMPLE : ${SAMPLE_FILE}"
		echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} -w ${IURC_ADD_SPIDEX} -i ${TXT_FILE} -e ${TABIX} -s ${SPIDEX_PATH}"
		echo "#############################################################################################"

		NEW_FILE=$(${SRUN_SIMPLE_COMMAND} ${PERL} -w ${IURC_ADD_SPIDEX} -i ${TXT_FILE} -e ${TABIX} -s ${SPIDEX_PATH})
		ckRes $? "PERL : Add spidex "
		ckFileSz ${NEW_FILE}
		if [ "${CLEAN_UP}" == 'true' ];then
			rm ${TXT_FILE}
		fi
		TXT_FILE=${NEW_FILE}
	fi
	if [ "${MULTISAMPLE}" == 'true' ]; then
		echo "#############################################################################################"
		echo "PERL : Add barcode - `date` ID_ANALYSE : ${ID} - SAMPLE : ${SAMPLE_FILE}"
		echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} -wT ${IURC_ADD_BARCODE} -v ${INPUT_PATH}${SAMPLE_FILE} -t ${TXT_FILE}"
		echo "#############################################################################################"

		#home made perl script to barcode annotated file
		NEW_FILE=$(${SRUN_SIMPLE_COMMAND} ${PERL} -wT ${IURC_ADD_BARCODE} -v ${INPUT_PATH}${SAMPLE_FILE} -t ${TXT_FILE})
		ckRes $? "PERL : Add barcode "
		ckFileSz ${NEW_FILE}
		if [ "${CLEAN_UP}" == 'true' ];then
			rm ${TXT_FILE}
		fi
		TXT_FILE=${NEW_FILE}

	fi

	if [ "${ANNOTATOR}" == 'annovar' ] || [ "${ANNOTATOR}" == 'merge' ]; then
		if [ "${GENOME}" == 'hg19' ]; then

			echo "#############################################################################################"
			echo "PERL : Add LED data - `date` ID_ANALYSE : ${ID} - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} -w ${IURC_ADD_LED} -t ${TXT_FILE} -e ${TABIX} -l ${LED}"
			echo "#############################################################################################"

			#home made perl script to add led frequency data
			NEW_FILE=$(${SRUN_SIMPLE_COMMAND} ${PERL} -w ${IURC_ADD_LED} -t ${TXT_FILE} -e ${TABIX} -l ${LED})
			ckRes $? "PERL : Add LED data "
			ckFileSz ${NEW_FILE}
			if [ "${CLEAN_UP}" == 'true' ];then
				rm ${TXT_FILE}
			fi
			TXT_FILE=${NEW_FILE}
		fi

		if [ "${LIST}" != '' ]; then

			echo "#############################################################################################"
			echo "PERL : Mark genes - `date` ID_ANALYSE : ${ID} - SAMPLE : ${SAMPLE_FILE}"
			echo "COMMAND: ${SRUN_SIMPLE_COMMAND} ${PERL} -T -w ${IURC_MARK_GENES} -l ${LIST} -f ${TXT_FILE}"
			echo "#############################################################################################"

			#home made perl script to mark genes in an annovar file
			NEW_FILE=$(${SRUN_SIMPLE_COMMAND} ${PERL} -T -w ${IURC_MARK_GENES} -l ${LIST} -f ${TXT_FILE})
			ckRes $? "PERL : Mark genes "
			ckFileSz ${NEW_FILE}
			if [ "${CLEAN_UP}" == 'true' ];then
				rm ${TXT_FILE}
			fi
			TXT_FILE=${NEW_FILE}
		fi

		POSITION='7'
		POSITION_END='9'
		if [ "${LIST}" != '' ];then
			POSITION='8'
			POSITION_END='10'
		fi
		echo "#############################################################################################"
		echo "BASH/AWK/JOIN/CUT : Add OMIM annotation - `date` ID_ANALYSE : ${ID} - SAMPLE : ${SAMPLE_FILE}"
		echo "COMMAND: LANG=en_EN ${JOIN} -a 1 -t $'\t' -1 1 -2 1 <(${CAT} ${TXT_FILE} | ${AWK}  -F\\\t -v OFS='\t' '{k=\$${POSITION}; \$${POSITION}=\"\"; print k\"\t\""'$0'"}' | ${CUT} -f-${POSITION},${POSITION_END}- | ${AWK} 'NR==1; NR>1 {print "'$0'" | \"sort -k1,1\"}') ${GENEMAPR} >${OUTPUT_PATH}${SAMPLE_FILE}.${SUFFIX}.final.txt"
		echo "#############################################################################################"

		#genemapR file MUST be SORTED with cat genemapR.txt | awk 'NR == 1; NR > 1 {print $0 | "LANG=en_EN sort -k1,1"}' > genemapR_sorted.txt

		LANG=en_EN ${JOIN} -a 1 -t $'\t' -1 1 -2 1 <(${CAT} ${TXT_FILE} | ${AWK}  -F\\t -v OFS='\t' '{k=$'${POSITION}'; $'${POSITION}'=""; print k"\t"$0}' | ${CUT} -f-${POSITION},${POSITION_END}- | ${AWK} 'NR==1; NR>1 {print $0 | "sort -k1,1"}') ${GENEMAPR} >${OUTPUT_PATH}${SAMPLE_FILE}.${SUFFIX}.final.txt
		#LOCALE=C
		#sorted file on gene names - if we want to revert and sort on chr/pos, replace ">${OUTPUT_PATH}${SAMPLE_FILE}.final.txt" with "| sort -k2,3 >${OUTPUT_PATH}${SAMPLE_FILE}.final.txt" or -k3,4 if marked file
		#ckRes $? "BASH/AWK/JOIN/CUT : Add OMIM annotation "
		ckFileSz "${OUTPUT_PATH}${SAMPLE_FILE}.${SUFFIX}.final.txt"
		
		if [ "${CLEAN_UP}" == 'true' ];then
			rm ${TXT_FILE}
		fi
	fi
done


DATE2=$(date +"%s")
DIFF=$((${DATE2}-${DATE1}))


echo "#############################################################################################"
echo "#############################################################################################"
echo "ANNOTATION RUN : ${ID} COMPLETED WITH SUCCESS FOR FILES"
echo ${SAMPLES_FILE_LIST[@]}
echo "EXECUTION TIME:"
printf '%dh:%dm:%ds\n' $((${DIFF}/3600)) $((${DIFF}%3600/60)) $((${DIFF}%60))
echo "#############################################################################################"
echo "#############################################################################################"

exit 0
