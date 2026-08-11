# De novo Binder DEsign Tutorial
## installation and configuration

Check the instructions at ... to install and configure ProteinDJ for your system/cluster

# Target preparation

Before you begin design binders, you need to prepare a target protein structure. The success of binder design depends greatly on the quality of the input model and how well it represents the protein in solution. Proteins with large instrinsically disordered regions (IDRs) are much harder to work with since the conformations and positions of these parts is not certain. Similarly, proteins with post-translation modifications (e.g. phosphorylation, glycosylation) on their surface may inhibit protein-protein interactions. Be mindful of this when selecting an experimental structure: check if the protein was modified/truncated from it's natural state which you may be targeting in vitro/in vivo. If your experimental structure is missing residues, a common rescue approach is to use template-guided structure prediction to replace them (e.g. using AlphaFold/Boltz). If you suspect the absence of the residues in the structure is due to flexibility (often indicated in a structure prediction by \< 50 pLDDT), record the residue ranges so that you can use this during design. 

Binder design algorithms scale exponentially with the size of your input, so it is common practice to trim structures down to the domain(s) of interest. Overcropping, especially when it leaves incomplete folds with exposed inner residues can lead to issues with structure prediction so there is a balance.

For this example, we will be working with a structure of the insulin receptor (PDB: 4ZXB) in ChimeraX, although you can also use PyMOL. This structure has some of the issues highlighted above: missing residues and glycosylation sites, with many domains to choose from across the 768 residues. We can design binders against any of these domains, avoiding glycans and patching missing areas as needed. For the purposes of this tutorial we are interested in the first domain (E1-190). 

However, this crystal structure has missing residues in domain 1. RFdiffusion will interpret the input like this E1-162/E168-172/E177-190 and will not fill in missing residues. These chain breaks can cause issues with structure prediction as we have a small peptide (168-172). As described earlier, we can use structure prediction to complete our target structures and the AlphaFoldDB entry on human insulin receptor (https://alphafold.ebi.ac.uk/entry/AF-P06213-2-F1) is a good match (0.44 Calpha RMSD), so we will use this file instead. Note that this prediction includes the signal peptide (1-27) that is cleaved during expression, so domain 1 is 28-217.

## Choosing hotspots

You may have a particular binding site in mind for your target protein. To guide the binder design programs to a location we need to provide surface hotspot residues. In ProteinDJ, you can provide a chain-qualified residue e.g. 'A56', a chain-qualified range e.g. 'A115-120', or a bare chain ID meaning the whole chain e.g. 'B', or a combination e.g. 'A56,A115-120,B'. This means that the binder design will try to be within a short distance e.g. 5-7 angstroms from each of these residues but not exclusively to these residues. It is sufficient to provide 2-4 residues spread across a binding site, rather than exhaustively listing every residue on the surface. If hotspots are not provided (i.e. `hotspot_residues=null`) then the binder design program will select a site automatically. Often it will gravitate towards hydrophobic patches or known protein-protein interaction sites from structures in the PDB, which these models were trained on. It is useful to try different hotspots locations when working with a new target and seeing how this affects the success rates downstream. 

In this example our crystal structure is helpful to our design constraints as we can see sites of glycosylation. we will choose hotspots to avoid nearby glycosylation sites and interfaces that are near adjacent domains: "A91,A115,A123". These three phenylalanine residues form part of a hydrophobic patch that bind to the ??? and hte goal of our binders is to disrupt this interaction. 

## Cropping input structures

Download the AlphaFoldDB prediction of human insulin receptor (https://alphafold.ebi.ac.uk/entry/AF-P06213-2-F1) as a PDB file

In ChimeraX (or using equivalent commands in program of choice):

Select a domain of interest using the sequence viewer or commandline:

select #1/A:28-217

File -> Save -> Select PDB from 'Files of type' and tick 'Selected atoms only' -> Save (e.g. 'tutorial.pdb')

Alternatively, you can delete everything that you do not want to pass to ProteinDJ and save all atoms (default). If you have an experimental structure (crystallography/cryo-EM) you might need to delete ligands and non-standard residues too:
Select -> Residues -> All nonstandard
Actions -> Atoms/Bonds -> Delete

Upload/copy this file to your ProteinDJ project directory

## Deciding on design length

For de novo binder design, you must provide a desired length (or range) for binders. This also affects the time needed for computation as it contributes to the exponential memory use and runtime that we see with large target structures. You also need to consider the downstream use of the designs, as gene synthesis costs usually increase with length. It is difficult to reduce the size of binders after design without compromising their folding/binding.

However, if the binders become too small they will be more like peptides rather than folded domains, which could lead to issues with expression/solubility, or they may simply lack sufficient buried surface area or shape complementarity with the target. We usually start with a range for binder design (e.g. 60-150), so that we sample different sizes. If you notice that you can achieve high prediction confidence and good buried surface area with smaller binders, then reducing this range will save you significant time. 

# Small scale test

Now that we have prepared our target structures, identified our hotspots, and decided on a binder length range, we are ready to begin binder design. There are multiple ways you can interact with ProteinDJ/NextFlow:
 - Passing input parameters to the commandline
 - Using a config file or profile
 - Using a webserver like Seqera

Let's use the commandline to start a short binder design run on our target using RFdiffusion (rfd_denovo mode):
```
# Use the path to your PDB file
nextflow run main.nf -profile test --design_mode "rfd_denovo" --input_pdb "tutorial.pdb" --hotspot_residues "A91,A115,A123" --design_length "60-150" --out_dir "tutorial_test"
```

Note that the single hyphen parameter ('-profile') is directed to Nextflow, and the double hyphen parameters (--design_mode, --input_pdb, --hotspot_residues etc.) are directed to ProteinDJ. The test profile simply reduces the number of designs and sequences per design, and reads as follows:

```
test {
    // base configuration for testing
    params {
        num_designs = 4
        seqs_per_design = 2
    }
}
```

There is a hierachy for Nextflow with commandline parameters overriding profile values and profile values overriding the default values in the nextflow.config. In the above example, num_designs normally defaults 8 so this profile reduces the number to 4.

We can create our own profile for the insulin receptor design either by adding a profile to nextflow.config or creating a new config file e.g.

tutorial.config
```
profiles {
    insulinreceptor {
        params {
            design_mode = 'rfd_denovo'
            input_pdb = 'tutorial.pdb'
            hotspot_residues = "A91,A115,A123"
            design_length = "60-150"
            out_dir="tutorial_test"
        }
    }
}
```

Then rather than providing these values as commandline parameters, we pass the profile name to Nextflow along with the name of the config file. Nextflow will look for matching profile names in both nextflow.config and any config files that are named on launch. This command is identical to the test we ran above:

```
nextflow run main.nf -profile test,insulinreceptor -config tutorial.config
```

In this way you can mix and match multiple profiles together i.e. a profile with your favourite settings for binder design and your target-specific parameters.

# Understanding the output and metrics

In the "tutorial_test" folder that was created earlier, you will find the outputs of ProteinDJ organised as below:

```
out_dir/
├── configs/                  # Config files used for run
├── inputs/                   # Input files used in run e.g. PDB files for binder design
├── run/                      # Intermediate results and log files with subfolders for each process
├── results/                  # Final results and metadata
    ├── best_designs.tar.gz   # Archive containing PDB files of designs that passed all filters
    ├── ranked_designs.tar.gz # Archive containing ranked PDB files of designs that passed all filters
    ├── all_designs.csv       # CSV file with metadata for all designs
    ├── best_designs.csv      # CSV file with metadata for designs that passed all filters
    └── ranked_designs.csv    # CSV file with metadata for ranked designs that passed all filters
└── nextflow.log              # Copy of Nextflow log from run
```

Most of the time we are interested in the files in 'results' as this contains the final predictions of our best binders and the metrics for all the designs. In this case, since we did not enable any filters, all of our designs passed, and all_designs.csv is identical to best_designs.csv. If you generate more high-quality designs than you need, you can use the ranked designs in ranked_designs.csv to select your favourites. 

Let's examine all_designs.csv (you can use VS Code or Excel or a text editor). The first row is the header and contains the names of all the metrics, and each subsequent row represents a single design with all the metrics. Eac h design has a unique fold_id and seq_id that form part of the name of the output PDB file, along with the structure prediction program e.g. 'fold_1_seq_0_boltzpred.pdb'. In the subsequent columns are the scores for the design, mostly consisting of the prediction scores by Boltz. As diffusion is a stochastic process, your scores will differ but in my case X designs had very low confidence and Y designs had much higher confidence.

| description | fold_id | seq_id | rfd_sampled_mask | fold_helices | fold_strands | fold_total_ss |
|---|---|---|---|---|---|---|


# Filtering designs

There are some example values in the example_filters profile (see nextflow.config) that have been used as cutoff for binder design campaigns it is worth noting that this does not guarantee binding. As outlined in 'Target Preparation section' the input structure may not reflect the true protein structure/conformation, and structure prediction programs can be biased towards particular folds/complexes. Nevertheless, using these metrics to filter out bad designs has been shown to improve success rates even though some binder design campaigns still fail.

Aside from structure prediction filters, there are other aspects of the workflow you can modulate. RFdiffusion can sometimes generate 1 or 2 helix designs, rather than folded binder domains. These have a high failure rate downstream and unless you are intentially designing peptides, it saves time filtering them out before sequence design and structure prediction. Let's add a new profile to our config file with a filtering parameter specifying that the binder must have 3 or more secondary structures (helices/beta-strands):

```
profiles {
    filters {
        params {
            fold_min_ss = 3
        }
    }
    insulinreceptor {
        params {
            design_mode = 'rfd_denovo'
            input_pdb = 'tutorial.pdb'
            hotspot_residues = "A91,A115,A123"
            design_length = "60-150"
            out_dir="tutorial_test"
        }
    }
}
```

This means that design X in my results would have 

(Creating a filtering profile)

# Large scale run

# Advanced Options

# Alternative Fold Design Progams (BindCraft/BoltzGen)

(Discuss advantages and disadvantages, how to switch)

# Boltz2 and Serial AF2-Boltz Prediction

# BindSweeper

