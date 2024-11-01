process CELLS2STATS {
    tag "$id"
    label 'process_high'
    scratch true

    container "${params.container_url}:${params.container_tag}"

    input:
    val id
    path input_dir
    path run_panel
    path run_manifest

    output:

    path "./c2s_results",    emit: results
    path "versions.yml",   emit: versions
    path "run.log",        emit: run_log

    script:
    def batch_option = params.batch ? "--batch ${params.batch}" : ""
    def error_on_missing_option = params.error_on_missing ? "--error-on-missing" : ""
    def log_level_option = params.log_level ? "--log-level ${params.log_level}": "--log-level info"
    def max_unassigned_option = params.max_unassigned ? "--max-unassigned ${params.max_unassigned}" : ""
    def no_error_on_invalid_option = params.no_error_on_invalid ? "--no-error-on-invalid" : ""
    def panel_option = run_panel ? "--panel ${run_panel}" : ""
    def run_manifest_option = run_manifest ? "--run-manifest ${run_manifest}" : ""
    def skip_cellprofiler_option = params.skip_cellprofiler ? "--skip-cellprofiler" : ""
    def tile_option = params.tile ? "--tile ${params.tile}" : ""
    def well_option = params.well ? "--well ${params.well}" : ""

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
        ${skip_cellprofiler_option} \\
        ${tile_option} \\
        ${well_option} \\
        -j ${task.cpus} \\
        --output ./c2s_results \\
        ${input_dir}
    "

    cells2stats \\
        ${batch_option} \\
        ${error_on_missing_option} \\
        ${log_level_option} \\
        ${max_unassigned_option} \\
        ${no_error_on_invalid_option} \\
        ${panel_option} \\
        ${run_manifest_option} \\
        ${skip_cellprofiler_option} \\
        ${tile_option} \\
        ${well_option} \\
        -j ${task.cpus} \\
        --output ./c2s_results \\
        ${input_dir}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cells2stats: \$(cells2stats -v | sed -e "s/,//g" | awk '{print \$3}')
    END_VERSIONS
    """
}
