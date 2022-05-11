# Example WES QC pipeline

A collection of scripts to use as a starting point for running quality control on whole exome sequencing datasets using Hail.

Throughout, we assume that the reference geneome is GRCh38. If this isn't the reference used for calling in your dataset, switch to the appropriate reference by changing `REFERENCE = 'GRCh38'` in each of the Hail python scripts.

These scripts assume that you have access to a large number of cores to run them on. If not, you will need to split (e.g. by chromosome) and run scripts in parallel. Examples of this procedure and intermediate plotting (as well as scripts for submitting jobs to a HPC) for very similar steps to these can be found in [this](https://github.com/astheeggeggs/SAIGE_gene_munging/tree/main/QC_scripts) repository.

A set of useful file are in the [example inputs folder](https://github.com/astheeggeggs/BRaVa_curation/tree/main/example_inputs):

* Low complexiy region file in the expected format: `LCR-hs38.bed.gz`
* Regions of high-LD (in build 38) in the expected format: `b38_high_ld.bed`
* Target intervals file in the expected format: `ice_coding_v1_targets.interval_list.gz`. 
* Padded target intervals file in the expected format `ice_coding_v1_padded_targets.interval_list.gz`
  * Note that the header lines of interval_list files are prepended with `@` - these lines are ignored by Hail.

## Step 0: Create an initial Hail MatrixTable
Read in joint called VCF and write to Hail MatrixTable format

___Inputs___: 
* Filepath to the jointcalled .vcf to input: `${INPUT_VCF}`

___Outputs___: 
* Filepath to place the output MatrixTable: `${RAW_MT}`

`python 00_load_and_write_vcf_as_mt.py ${INPUT_VCF} ${RAW_MT}`

## Step 1: Genotype QC
* Remove sites with a large number of alleles (>6)
* Filter genotypes based on depth, likelihood, and allele balance.
  * If homozygous reference, at least one of:
    * Genotype quality < 20
    * Depth < 10
  * If heterozygous, at least one of:
    * (Reference allele depth + alternative allele depth)/depth < 0.8
    * (Alternative allele depth)/depth < 0.2
    * Reference phred-scaled genotype posterior < 20
    * Depth < 10
  * If homozygous variant, at least one of:
    * (Alternative allele depth)/depth < 0.8
    * Reference phred-scaled genotype posterior < 20
    * Depth < 10

___Inputs___:
* Filepath to place the MatrixTable output from step 0: `${RAW_MT}`

___Outputs___:
* Filepath to place the output MatrixTable: `${MT}`
* Filepath to place the output hard-calls MatrixTable: `${MT_HARDCALLS}`

`python 01_filterGT.py ${RAW_MT} ${MT} ${MT_HARDCALLS}`

## Step 2: Initial Variant QC

Remove variants that either:
* Fall in a low complexity region
* Fail VQSR (note that if GATK was not used for calling, you will not be able to apply this filter).
* Fall outside of padded target intervals (we recommend 50bp padding)
* Filter out invariant sites

___Inputs___: 
* Filepath to hard-calls MatrixTable from step 1: `${MT_HARDCALLS}`
* Filepath to the target intervals file (see below for expected format): `${TARGET_INTERVALS}`
* Filepath to the padded target intervals file: `${PADDED_TARGET_INTERVALS}`
* Filepath to low-complexity regions intervals file: `${LCRs}`

___Outputs___:
* Filepath to place initial QC metrics for downstream plotting: `${INITIAL_VARIANT_QC_FILE}`
* Filepath to place the set of variants remaining after step 2 filtering: `${INITIAL_VARIANT_LIST}`

`python 02_prefilter_variants.py ${MT_HARDCALLS} ${TARGET_INTERVALS} ${PADDED_TARGET_INTERVALS} ${LCRs} ${INITIAL_VARIANT_QC_FILE} ${INITIAL_VARIANT_LIST}`

We have included an example target intervals file, target intervals file with 50bp padding and LCRs file to show the expected format.

* Target intervals file: `example_inputs/ice_coding_v1_targets.interval_list.gz`
* Padded target intervals file: `example_inputs/ice_coding_v1_padded_targets.interval_list.gz`
* LCRs file: `example_inputs/LCR-hs38.bed.gz`

## Step 3: Initial Sample QC

In this step, we run the sample QC function in hail to determine sample qc metrics

___Inputs___:  
* Filepath to hard-calls MatrixTable from step 1: `${MT_HARDCALLS}`
* Filepath to the set of variants remaining after step 2 filtering: `${INITIAL_VARIANT_LIST}`
* Filepath to the target intervals file (see below for expected format): `${TARGET_INTERVALS}`

___Outputs___:
* Filepath to place initial sample QC metrics for downstream plotting: `${INITIAL_SAMPLE_QC_FILE}$`

`python 03_0_initial_sample_qc.py ${MT_HARDCALLS} ${INITIAL_VARIANT_LIST} ${INITIAL_SAMPLE_QC_FILE}`

We then plot the sample metrics using `03_1_initial_sample_qc_plot.r`. 
We then create a series of plots, and define an empirical hard cutoff for a series of the metrics. Edit the chosen thresholds in `utils/r_options.r` or redefine them at the start of the plotting script (`03_1_initial_sample_qc_plot.r`).

When you are happy with the proposed cutoffs, run `03_2_initial_sample_filter.r`.

## Step 4: High Quality Common Variant Subset

There are a few options here

### Genotype data is available

This first step takes the X chromosome, and LD prunes to define a collection of pseudo-independent SNPs for subsequent _F_-statistic evaluation. We filter to the collection of samples with exome sequence data available to speed things.

Here's a bash script to do this using plink (assuming that plink is installed and in your `$PATH`). It's just a wrapper to a plink command.

___Inputs___:
* Filepath to .bed for chromosome X: `${GENO_X_BED}`
* Filepath to .bim for chromosome X: `${GENO_X_BIM}`
* Filepath to .fam for chromosome X: `${GENO_X_FAM}`
* Filepath to sample information (aka phenotype inforamtion) for the samples that are sequenced: `${SAMPLE_INFORMATION}`

___Outputs___:
* Prefix for high-quality pruned common chromosome X variant plink files: `${PRUNED_X_PLINK}`

`bash 04_prune_genotyped_snps.sh ${GENO_X_BED} ${GENO_X_BIM} ${GENO_X_FAM} ${SAMPLE_INFORMATION} ${PRUNED_X_PLINK}`

### Only WES data is available

If only WES data is available, you'll need to create a set of high quality SNPs, and then LD-prune them. The first step is to spit out a high quality set of variants to a set of plink files.

___Inputs___:
* Filepath to hard-calls MatrixTable from step 1: `${MT_HARDCALLS}`
* Filepath to the list of samples remaining after `03_2_initial_sample_filter.r`: `${SAMPLE_LIST_INITIAL_QC}`
* Filepath to the set of variants remaining after step 2 filtering: `${INITIAL_VARIANT_LIST}`
* Filepath to set of high-LD regions for removal: `${HIGH_LD_INTERVALS}`

___Outputs___:
* Prefix for high-quality common variant plink files: `${PLINK_FILES}`

`python 04_0_export_plink.py ${MT_HARDCALLS} ${SAMPLE_LIST_INITIAL_QC} ${INITIAL_VARIANT_LIST} ${HIGH_LD_INTERVALS} ${PLINK_FILES}`

Next, take these plink files and LD-prune them. The following bash script is a simple wrapper to call plink a few times. Again, we're assuming that plink is installed and in your `$PATH`.

___Inputs___:
* Prefix for high-quality common variant plink files: `${PLINK_FILES}`

`bash 04_1_prune_sequencing_snps.sh ${PLINK_FILES}`

The outputs of step 4 (if genotype data is available and if only WES data is available) feed into steps 5 and 6.

## Step 5: Determine superpopulation ancestry labels

There are a few options here. If genotype data is available, or if only WES data is available.

### Genotype data is available

We provide an R script to assign 1000G ancestry labels using genotype data, using the UK Biobank data as an example.

Here we make use of the OADP projection to guard against shrinking PCs to 0, though in the case of projection of the first four PCs which will be used downstream for superpopulation assignment, this is likely overkill as the shrinkage is not severe in the first few PCs.

* Combine the chromosome data together into a single plink file from R (as this is required by `bigsnpr` to perform the projections) in the data that we wish to project (UKBB data in this example).
* Download the 1000G data, and project the UK Biobank samples onto the PC space defined by 1000G.
* Assign superpopulation labels to the 1000G data, based on the 1000G ped file.
* Create a random forest classifier using the `randomForest` library in R, and write out the results. We used a threshold of 0.99 to assign labels to UK Biobank samples. Samples that weren't clearly assigned to any cluster were labelled 'unsure'.

`05_estimate_superpopulation.r`

### Only WES data is available

Run as above, but filtering to the set of SNPs present in both the WES/WGS and 1000G data first.

## Step 6: Sex imputation
This step should be run separately for each superpopulation (MAF differences across superpopulations can throw off the _F_ statistic).

There are two options: if genotype data is available, or if it isn't. The code is the same, just applied to either LD-pruned genotyping (output of `04_prune_genotyped_snps.sh`) or LD pruned sequencing data after filtering to high quality variants (output of `04_1_prune_sequencing_snps.sh`).

To do this we read in the pruned sex chromosome data, and determine the _F_-statistic for samples using the X chromosome, and check the number of non-missing allele counts on the Y.

print("Inputs:")
print('MT_HARDCALLS; input hard calls matrix table: ', MT_HARDCALLS)
print('INITIAL_SAMPLES; set of initial samples output from 03_01_initial_sample_qc_filter.r: ', INITIAL_SAMPLES)
print('PRUNED_CHRX_VARIANTS; set of LD-pruned high-quality variants on the X: ', PRUNED_CHRX_VARIANTS)
print('PHENOTYPES_TABLE; a collection of sample annotations, which includes self-assigned sex or gender: ', PHENOTYPES_TABLE)

print("Outputs:")
print('IMPUTESEX_TABLE; output .tsv file to plot imputed sex information : ', IMPUTESEX_TABLE)
print('IMPUTESEX_FILE; output .tsv file to use to count mismatches at this step for a summary table: ', IMPUTESEX_FILE)
print('Y_NCALLED; output .tsv file of calls on the Y: ', Y_NCALLED)

Plot the output of `06_impute_sex.py`. We plot the distribution of the _F_-statistic on the X, and define a cutoff for sex labelling. We also plot the X _F_-statistic against the number of reads on the Y chromosome. After adding genetically defined sex, we compare to the self assigned sex in the phenotype file and remove mismatches.

parser <- ArgumentParser()
parser$add_argument("--impute_sex_table", required=TRUE, help="Path to IMPUTESEX_TABLE from 06_0_impute_sex.py")
parser$add_argument("--y_ncalled", required=TRUE, help="Path to Y_NCALLED from 06_0_impute_sex.py")
parser$add_argument("--sexcheck_list", required=TRUE, help="Path to output file containing sex swaps")
args <- parser$parse_args()

IMPUTESEX_FILE <- args$impute_sex_table
Y_NCALLED_FILE <- args$y_ncalled
SEXCHECK_LIST <- args$sexcheck_list

## Step 7: Determine related samples

If you have a single homogeneous population, you can use IBD estimation with the following script:
`07_0_ibd.py`

print("Inputs:")
print('MT_HARDCALLS; input hard calls matrix table: ', MT_HARDCALLS)
print('INITIAL_SAMPLES; set of initial samples output from 03_01_initial_sample_qc_filter.r: ', INITIAL_SAMPLES)
print('PRUNED_VARIANTS; set of LD-pruned high-quality variants in the autosomes: ', PRUNED_VARIANTS)

print("Outputs:")
print('IBD_OUTPUT; output .tsv file with IBD information for plotting: ', IBD_OUTPUT)

If you have multiple superpopulations, you should use PC-relate to identify related samples with the following script:
`07_0_pc_relate.py`

print("Inputs:")
print('MT_HARDCALLS; input hard calls matrix table: ', MT_HARDCALLS)
print('INITIAL_SAMPLES; set of initial samples output from 03_01_initial_sample_qc_filter.r: ', INITIAL_SAMPLES)
print('PRUNED_VARIANTS; set of LD-pruned high-quality variants in the autosomes: ', PRUNED_VARIANTS)

print("Outputs:")
print('PC_RELATE_OUTPUT; output .tsv file with pc-relate information for plotting: ', PC_RELATE_OUTPUT)

I still have a few steps to include. 

final_variant_qc
final_sample_qc
creation of a final set of PCs to include in association analyses
create and check a finalised curated matrix table
spit out a vcf, plink, or bgen file from the matrixtable for downstream analyses that have input format requirements
