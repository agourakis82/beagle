# Omics Track

This track is for omics preprocessing and model stages that need:

- large shared input sets
- durable intermediate outputs
- strong batch semantics
- optional GPU acceleration for learned feature extraction

Starting point:

- [omics preprocess pilot](/home/devsounio/beagle/k8s/hpc-sota/workloads/omics/job-omics-preprocess-orangefs.yaml)

Current status:

- `omics-preprocess-orangefs` now completes successfully
- durable outputs are written from local `/scratch` into OrangeFS through the
  hardened promotion path that proved most reliable for this workload
- current runtime proof:
  - `records=1024`
  - `top_gene=GENE_0260`
- current OrangeFS artifacts:
  - `/datasets/omics-expression-summary.csv`
  - `/checkpoints/omics-preprocess-summary.json`

Storage shape:

- `/datasets/omics`
- `/checkpoints/omics`
- local `/scratch`
