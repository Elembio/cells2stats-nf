**cells2stats-nf** is a bioinformatics pipeline used to assign reads and generate cell statistics from the raw data produced by the Element AVITI24™ System using the Cells2Stats Software.

- The [Cells2Stats Documentation](https://docs.elembio.io/docs/cells2stats/setup/) has detailed execution information for changing parameters.
- The [Run Manifest Documentation](https://docs.elembio.io/docs/run-manifest/cyto-prepare-manifest/) has detailed information for setting well settings and batch information.

Cells2stats-nf enables you to run Cells2Stats on any environment that supports running nextflow.

## nextflow run commands

```
nextflow run . -profile test
```

## Run nf-test

```
nf-test test

```

## License

Use subject to license available at go.elembio.link/eula.
