#######################################
## Functions to train a MOFA model ##
#######################################

#' @title Train a MOFA model
#' @name run_mofa
#' @description Function to train an untrained \code{\link{MOFA}} object.
#' @details In this step the R package is calling the \code{mofapy2} Python package, where the model the training is performed. \cr
#' The interface with Python is done with the \code{\link{reticulate}} package. 
#' If you have several versions of Python installed and R is not detecting the correct one, you can change it using \code{reticulate::use_python}.
#' @param object an untrained \code{\link{MOFA}} object
#' @param save_data logical indicating whether to save the training data in the hdf5 file. 
#'  This is useful for some downstream analysis (mainly functions with the prefix \code{plot_data}), but it can take a lot of disk space.
#' @param outfile output file for the model (.hdf5 format). If \code{NULL}, a temporary file is created.
#' @param save_expectations vector with capitalized node names. If NA, only W and Z are saved by default.
#' @return a trained \code{\link{MOFA}} object
#' @import reticulate
#' @export
#' @examples
#' # Using an existing simulated data with two groups and two views
#' file <- system.file("exdata", "test_data.txt.gz", package = "MOFA2")
#' 
#' # Load data (in data.frame format)
#' data <- read.table(file, header=TRUE) 
#' 
#' # Create MOFA object
#' MOFAmodel <- create_mofa(data)
#' 
#' # Prepare the MOFA object with default options
#' MOFAmodel <- prepare_mofa(MOFAmodel)
#' 
#' # Run the MOFA model
#' \dontrun{ MOFAmodel <- run_mofa(MOFAmodel, outfile = "~/model.hdf5") }
run_mofa <- function(object, outfile = NULL, save_data = TRUE, save_expectations = NULL) {
  
  # Sanity checks
  if (!is(object, "MOFA")) 
    stop("'object' has to be an instance of MOFA")
  if (object@status=="trained") 
    stop("The model is already trained! If you want to retrain, create a new untrained MOFA")

  # If not outfile is provided, store a file in the /temp folder with the respective timestamp
  if (is.null(outfile)) {
    outfile <- file.path("/tmp", paste0("mofa_", format(Sys.time(), format = "%Y%m%d-%H%M%S"), ".hdf5"))
    warning(paste0("No output filename provided. Using ", outfile, " to store the trained model.\n\n"))
  }
  if (file.exists(outfile))
    message("Warning: Output file already exists, it will be replaced")
  
  # Initiate reticulate
  mofa <- import("mofapy2")
  
  # Call entry point
  mofa_entrypoint <- mofa$run.entry_point$entry_point()
  
  # Set data options
  mofa_entrypoint$set_data_options(
    scale_views = object@data_options$scale_views,
    scale_groups = object@data_options$scale_groups
  )
  
  # Set the data
  mofa_entrypoint$set_data_matrix(
    data = r_to_py( unname(lapply(object@data, function(x) unname( lapply(x, function(y) r_to_py(t(y)) ))) ) ),
    likelihoods = unname(object@model_options$likelihoods),
    views_names = r_to_py(as.list(object@data_options$views)),
    groups_names = r_to_py(as.list(object@data_options$groups)),
    samples_names = r_to_py(unname(lapply(object@data[[1]], colnames))),
    features_names = r_to_py(unname(lapply(object@data, function(x) rownames(x[[1]]))))
  )
  
  # Set model options 
  mofa_entrypoint$set_model_options(
    factors     = object@model_options$num_factors,
    spikeslab_factors = object@model_options$spikeslab_factors, 
    spikeslab_weights = object@model_options$spikeslab_weights, 
    ard_factors       = object@model_options$ard_factors,
    ard_weights       = object@model_options$ard_weights 
  )
  
  # Set training options  
  mofa_entrypoint$set_train_options(
    iter             = object@training_options$maxiter,
    convergence_mode = object@training_options$convergence_mode,
    dropR2           = object@training_options$drop_factor_threshold,
    startELBO        = object@training_options$startELBO,
    freqELBO         = object@training_options$freqELBO,
    seed             = object@training_options$seed, 
    gpu_mode         = object@training_options$gpu_mode,
    verbose          = object@training_options$verbose
  )
  
  # Set stochastic options
  if (object@training_options$stochastic) {
    mofa_entrypoint$set_stochastic_options(
      learning_rate    = object@stochastic_options$learning_rate,
      forgetting_rate  = object@stochastic_options$forgetting_rate,
      batch_size       = object@stochastic_options$batch_size,
      start_stochastic = object@stochastic_options$start_stochastic
    )
  }
  
  # Build the model
  mofa_entrypoint$build()
  
  # Run the model
  mofa_entrypoint$run()
  
  # Save the model output as an hdf5 file
  mofa_entrypoint$save(outfile, save_data = save_data, expectations = save_expectations)
  
  # Load the trained model
  object <- load_model(outfile)
  
  return(object)
}
