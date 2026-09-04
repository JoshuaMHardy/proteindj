#!/bin/bash -l
#SBATCH --job-name=proteindj
#SBATCH --time=8:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=230GB
#SBATCH --account=pawsey0012
#SBATCH --partition=work


# Load singularity module.
module load singularity/3.11.4-nompi
module load nextflow/25.04.6

export NXF_SINGULARITY_CACHEDIR=$MYSCRATCH/containers/
export SINGULARITY_CACHEDIR=$MYSCRATCH/containers/

nextflow run main.nf -c pawsey.config \
    --design_mode rfd_denovo \
    -resume \
    --num_designs 1 --seqs_per_design 1 --design_length 5

    # options: bindcraft_denovo, boltzgen_denovo, boltzgen_motifscaff, rfd_denovo, rfd_foldcond, rfd_motifscaff, rfd_partialdiff
    # Please provide input PDB file path required by bindcraft_denovo mode