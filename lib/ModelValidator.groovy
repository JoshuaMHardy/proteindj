// Launch-time check that the model directories bind-mounted into the GPU containers exist and
// contain the weights the selected stages will load. Without it a wrong path only surfaces hours
// into a run, as an obscure error from inside a container. Only the stages that will actually run
// are checked, mirroring the skip_* / run_fold_only logic in main.nf.
class ModelValidator {

    // Throws IllegalArgumentException listing every missing model directory or file
    static void validate(Map params) {
        def problems = missingModels(params)
        if (problems) {
            throw new IllegalArgumentException(
                "Model files are missing:\n  - " + problems.join('\n  - ') +
                "\nDownload them with scripts/download_models.sh, or point the parameter(s) above at an existing models directory.")
        }
    }

    static List<String> missingModels(Map params) {
        def fold = !params.skip_fold && !params.skip_fold_seq && !params.skip_fold_seq_pred
        def seq = !params.skip_fold_seq && !params.skip_fold_seq_pred && !params.run_fold_only &&
            params.design_mode != 'rfd4_denovo'
        def pred = !params.skip_fold_seq_pred && !params.run_fold_only

        // Parameter name -> entries its directory must contain. A trailing '/' marks a directory
        // and '*' matches any characters in a file name (at least one match is required).
        def required = [:] as LinkedHashMap<String, Set<String>>
        def need = { String param, List<String> entries ->
            required.computeIfAbsent(param) { new LinkedHashSet<String>() }.addAll(entries)
        }

        if (fold) {
            switch (params.design_mode) {
                case 'bindcraft_denovo':
                    need('af2_models', ['params_model_*.npz'])
                    break
                case ['boltzgen_denovo', 'boltzgen_motifscaff']:
                    need('bg_models', ['boltzgen1_diverse.ckpt', 'boltzgen1_adherence.ckpt', 'mols.zip'])
                    break
                case 'rfd4_denovo':
                    need('rfd4_models', ['config.json', 'model.safetensors'])
                    break
                default:
                    need('rfd_models', ['*.pt'])
            }
        }
        if (seq && params.seq_method == 'mpnn') {
            need('mpnn_models', ["${params.mpnn_checkpoint_type}_model_weights/${params.mpnn_checkpoint_model}.pt".toString()])
        }
        if (pred) {
            if (params.pred_method in ['af2', 'af2_boltz']) {
                need('af2_models', ['params_model_*.npz'])
            }
            if (params.pred_method in ['boltz', 'af2_boltz']) {
                need('boltz_models', ['boltz2_conf.ckpt', 'mols/'])
            }
        }

        def problems = []
        required.each { param, entries ->
            def value = params[param]
            def dir = value ? new File(value.toString()) : null
            if (!dir || !dir.isDirectory()) {
                problems << "--${param}: directory not found (${value ?: 'not set'})".toString()
                return
            }
            def missing = entries.findAll { !exists(dir, it) }
            if (missing) {
                problems << "--${param}: ${dir} does not contain ${missing.join(', ')}".toString()
            }
        }
        return problems
    }

    private static boolean exists(File dir, String entry) {
        if (entry.endsWith('/')) {
            return new File(dir, entry).isDirectory()
        }
        def file = new File(dir, entry)
        if (!entry.contains('*')) {
            return file.isFile()
        }
        def parent = file.parentFile
        def regex = file.name.split('\\*', -1).collect { java.util.regex.Pattern.quote(it) }.join('.*')
        return parent.isDirectory() && parent.listFiles().any { it.isFile() && it.name ==~ regex }
    }
}
