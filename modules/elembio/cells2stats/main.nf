process CELLS2STATS {
    tag "$meta.id"
    label 'process_high'
    scratch true

    container "${params.c2s_container_url}:${params.c2s_container_tag}"

    input:
    tuple val(meta), val(run_dir)
    path run_panel
    path run_manifest
    path segmentation
    path tca_manifest

    output:
    // Cells2Stats outputs
    tuple val(meta), path("AverageNormWellStats.csv")               , optional: true, emit: average_norm_well_stats_csv
    tuple val(meta), path("RawCellStats.csv")                       , emit: raw_cell_stats_csv
    tuple val(meta), path("RawCellStats.parquet")                   , emit: raw_cell_stats_parquet
    tuple val(meta), path("RunStats.json")                          , optional: true, emit: run_stats_json
    tuple val(meta), path("RunParameters.json")                     , optional: true, emit: run_parameters_json
    tuple val(meta), path("Panel.json")                             , optional: true, emit: panel_json
    tuple val(meta), path("RunManifest.json")                       , optional: true, emit: run_manifest_json
    tuple val(meta), path("RunManifest.csv")                        , optional: true, emit: run_manifest_csv
    tuple val(meta), path("Versions.json")                          , optional: true, emit: versions_json
    // directories (captured as single path to avoid globbing hundreds of files)
    tuple val(meta), path("Wells")                                  , optional: true, emit: wells_dir
    // Per-tile rawreads parquets under Wells/<well>/<batch>/. Glob-emit
    tuple val(meta), path("Wells/**/*_rawreads.parquet")            , optional: true, emit: rawreads_files
    tuple val(meta), path("CellSegmentation")                       , optional: true, emit: cell_segmentation
    tuple val(meta), path("AnalysisRegion")                         , optional: true, emit: analysis_region
    tuple val(meta), path("Logs.tar.gz")                            , optional: true, emit: program_logs_tar
    tuple val(meta), path("Logs")                                   , optional: true, emit: program_logs
    // SpecializedTarget batch outputs
    tuple val(meta), path("TargetCellAssignmentManifest.csv")       , optional: true, emit: target_cell_assignment_manifest_csv
    tuple val(meta), path("TargetCellAssignmentManifest.json")      , optional: true, emit: target_cell_assignment_manifest_json
    tuple val(meta), path("TargetCounts.json")                      , optional: true, emit: target_counts_json
    // visualization
    tuple val(meta), path("cyto.viz")                               , optional: true, emit: cyto_viz
    tuple val(meta), path("visualization.zip")                      , optional: true, emit: viz_zip
    tuple val(meta), path("visualization-index.json.gz")            , optional: true, emit: viz_index_json_gz
    // spatial data outputs
    tuple val(meta), path("SpatialData")                            , optional: true, emit: spatial_data_dir
    tuple val(meta), path("SpatialData/*.zip")                      , optional: true, emit: spatial_data_zip
    tuple val(meta), path("SpatialData/*.zarr")                     , optional: true, emit: spatial_data_zarr
    // logs
    tuple val(meta), path("multiqc_report.html")                    , optional: true, emit: multiqc_report
    // versions.yml is process-identity-scoped (same content regardless of meta.id),
    // so emit as a bare path per nf-core convention. Keeps softwareVersionsToYAML
    // happy without consumer-side meta-stripping.
    path "versions.yml"                                             , emit: versions
    tuple val(meta), path("run.log")                                , emit: run_log
    // Curated small-metadata mirror for downstream tools (build-spatialdata
    // --c2s-dir). Contains only the named files in the allowlist below —
    // bulk artefacts like RawCellStats.* and Wells/ are excluded on purpose.
    tuple val(meta), path("metrics")                                , emit: metrics_dir

    when:
    task.ext.when == null || task.ext.when

    script:
    // Per nf-core convention, all user-configurable CLI flags are composed by
    // the consumer pipeline's conf/modules.config via task.ext.args. See
    // https://github.com/Elembio/cells2stats-nf#module-configuration-via-taskextargs
    def args             = task.ext.args ?: ''
    def tar_logs         = task.ext.tar_logs ?: false

    // Path inputs that the module knows the CLI flag for
    def panel            = run_panel    ? "--panel ${run_panel}"                : ''
    def run_manifest_opt = run_manifest ? "--run-manifest ${run_manifest}"      : ''
    def segmentation_opt = segmentation ? "--segmentation ${segmentation}"      : ''
    def tca_manifest_opt = tca_manifest ? "--tca-manifest ${tca_manifest}"      : ''

    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing Cells2Stats..."
    echo "Container: ${task.container}"

    cells2stats \\
        ${args} \\
        -j ${task.cpus} \\
        --output . \\
        ${panel} \\
        ${run_manifest_opt} \\
        ${segmentation_opt} \\
        ${tca_manifest_opt} \\
        ${run_dir}

    # Ensure directory outputs exist (cells2stats may not create all of them)
    mkdir -p Wells CellSegmentation Logs

    # Clean up empty bowtie-build logs
    rm -rf Logs/bowtie-build/

    if [ "${tar_logs}" = "true" ]; then
        tar czf Logs.tar.gz Logs/
        rm -rf Logs/
    fi

    # Curated small-metadata mirror for build-spatialdata --c2s-dir.
    # Top-level files only (bulk dirs Wells/, CellSegmentation/,
    # AnalysisRegion/, SpatialData/ are skipped by the file-type test);
    # known-bulk extensions are denylisted, and a 100 MB size cap catches
    # anything else. build-spatialdata is the final authority on what
    # actually flows into metadata/inputs/.
    mkdir -p metrics
    for f in *; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *.parquet|*.bam|*.bai|*.cram|*.crai|*.sam|*.fastq.gz|*.fq.gz|*.fastq|*.fq) continue ;;
        esac
        size=\$(stat -c%s "\$f" 2>/dev/null || echo 0)
        [ "\$size" -gt 104857600 ] && continue
        ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: \$(cells2stats -v | sed -e "s/,//g" | awk '{print \$3}')
    END_VERSIONS
    """

    stub:
    """
    touch RawCellStats.csv
    touch RawCellStats.parquet
    touch RunStats.json
    touch RunParameters.json
    touch Panel.json
    touch RunManifest.json
    touch RunManifest.csv
    touch Versions.json
    mkdir -p Wells CellSegmentation AnalysisRegion Logs
    touch run.log

    mkdir -p metrics
    for f in *; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *.parquet|*.bam|*.bai|*.cram|*.crai|*.sam|*.fastq.gz|*.fq.gz|*.fastq|*.fq) continue ;;
        esac
        size=\$(stat -c%s "\$f" 2>/dev/null || echo 0)
        [ "\$size" -gt 104857600 ] && continue
        ln -sf "../\$f" "metrics/\$f"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: stub
    END_VERSIONS
    """
}
