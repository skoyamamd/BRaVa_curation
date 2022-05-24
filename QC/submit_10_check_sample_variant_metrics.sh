#!/usr/bin/env bash
#$ -N hail_shell
#$ -cwd
#$ -o /well/lindgren/dpalmer/logs/hail.log
#$ -e /well/lindgren/dpalmer/logs/hail.errors.log
#$ -P lindgren.prjc
#$ -pe shmem 20
#$ -q short.qf@@short.hgf
#$ -t 1-23

set -o errexit
set -o nounset

module purge
source /well/lindgren/dpalmer/ukb_utils/bash/qsub_utils.sh
source /well/lindgren/dpalmer/ukb_utils/bash/hail_utils.sh

module use -a /apps/eb/testing/${MODULE_CPU_TYPE}/modules/all
module load Hail/0.2.93-foss-2021b

_mem=$( get_hail_memory )
new_spark_dir=/well/lindgren/dpalmer/tmp/
export PYSPARK_SUBMIT_ARGS="--conf spark.local.dir=${new_spark_dir} --conf spark.executor.heartbeatInterval=1000000 --conf spark.network.timeout=1000000  --driver-memory ${_mem}g --executor-memory ${_mem}g pyspark-shell"
export PYTHONPATH="${PYTHONPATH-}:/well/lindgren/dpalmer/ukb_utils/python:/well/lindgren/dpalmer:/well/lindgren/dpalmer/ukb_common/src"

chr=$(get_chr ${SGE_TASK_ID})

TRANCHE='200k'
CURATED_MT='/well/lindgren/UKBIOBANK/dpalmer/wes_${TRANCHE}/ukb_wes_qc/data/final_mt/10_european.strict_filtered_chr${chr}.mt'
SAMPLE_QC_FILE='/well/lindgren/UKBIOBANK/dpalmer/wes_200k/ukb_wes_qc/data/10_sample_metrics_for_plotting_chr${chr}.tsv.gz'
VARIANT_QC_FILE='/well/lindgren/UKBIOBANK/dpalmer/wes_200k/ukb_wes_qc/data/10_variant_metrics_for_plotting_chr${chr}.tsv.gz'

python 10_check_sample_variant_metrics.py ${CURATED_MT} ${SAMPLE_QC_FILE} ${VARIANT_QC_FILE}
print_update "Finished running Hail for chr${chr}" "${SECONDS}"