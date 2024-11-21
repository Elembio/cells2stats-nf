process CELLS2STATS {
    tag "$id"
    label 'process_high'
    scratch true

    container "${params.container_url}:${params.container_tag}"

    input:
    val id
    path run_dir
    path run_panel
    path run_manifest
    path segmentation

    output:

    // Cells2Stats outpus
    path "AverageNormWellStats.csv"    , optional: true, emit: average_norm_well_stats_csv
    path "RawCellStats.csv"            , optional: true, emit: raw_cell_stats_csv
    path "RawCellStats.parquet"        , optional: true, emit: raw_cell_stats_parquet
    path "RunStats.json"               , optional: true, emit: run_stats_json
    path "RunParameters.json"          , optional: true, emit: run_parameters_json
    path "Panel.json"                  , optional: true, emit: panel_json
    path "RunManifest.json"            , optional: true, emit: run_manifest_json
    path "RunManifest.csv"             , optional: true, emit: run_manifest_csv
    path "Versions.json"               , optional: true, emit: versions_json
    path "Wells/*"                     , optional: true, emit: wells_parquet
    path "CellSegmentation/*"          , optional: true, emit: cell_segmentation
    path "Logs/*"                      , optional: true, emit: program_logs
    // If visualization was requested
    path "visualization/*"             , optional: true, emit: visualization_data
    // Pipeline logs
    path "versions.yml"                                , emit: versions
    path "run.log"                                     , emit: run_log

    script:
    def batch_option = params.batch ? "--batch ${params.batch}" : ""
    def error_on_missing_option = params.error_on_missing ? "--error-on-missing" : ""
    def log_level_option = params.log_level ? "--log-level ${params.log_level}": "--log-level info"
    def max_unassigned_option = params.max_unassigned ? "--max-unassigned ${params.max_unassigned}" : ""
    def no_error_on_invalid_option = params.no_error_on_invalid ? "--no-error-on-invalid" : ""
    def panel_option = run_panel ? "--panel ${run_panel}" : ""
    def run_manifest_option = run_manifest ? "--run-manifest ${run_manifest}" : ""
    def segmentation_option = segmentation ? "--segmentation ${segmentation}" : ""
    def skip_cellprofiler_option = params.skip_cellprofiler ? "--skip-cellprofiler" : ""
    def tile_option = params.tile ? "--tile ${params.tile}" : ""
    def well_option = params.well ? "--well ${params.well}" : ""
    def visualization_option = params.visualization ? "--visualization" : ""
    def visualization_only_option = params.visualization_only ? "--visualization-only" : ""


    """
    logfile=run.log
    exec > >(tee \$logfile)
    exec 2>&1

    echo "Executing Cells2Stats..."
    echo "${params.container_url}:${params.container_tag}"
    echo "cells2stats \\
        ${batch_option} \\
        ${error_on_missing_option} \\
        ${log_level_option} \\
        ${max_unassigned_option} \\
        ${no_error_on_invalid_option} \\
        ${panel_option} \\
        ${run_manifest_option} \\
        ${segmentation_option} \\
        ${skip_cellprofiler_option} \\
        ${tile_option} \\
        ${well_option} \\
        ${visualization_option} \\
        ${visualization_only_option} \\
        -j ${task.cpus} \\
        --output . \\
        ${run_dir}
    "

    cells2stats \\
        ${batch_option} \\
        ${error_on_missing_option} \\
        ${log_level_option} \\
        ${max_unassigned_option} \\
        ${no_error_on_invalid_option} \\
        ${panel_option} \\
        ${run_manifest_option} \\
        ${segmentation_option} \\
        ${skip_cellprofiler_option} \\
        ${tile_option} \\
        ${well_option} \\
        ${visualization_option} \\
        ${visualization_only_option} \\
        -j ${task.cpus} \\
        --output . \\
        ${run_dir}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: \$(cells2stats -v | sed -e "s/,//g" | awk '{print \$3}')
    END_VERSIONS
    """
}
