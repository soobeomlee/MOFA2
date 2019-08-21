
#' @title create a MOFA object
#' @name create_mofa
#' @description Method to create a \code{\link{MOFA}} object
#' @param data Input data can be in several formats:
#' \itemize{
#'  \item{\strong{data.frame}:}{ it requires 5 columns: sample, group, feature, view, value. 
#'  The "group" column indicates the condition or the experiment (a label for the samples). 
#'  The view indicates the assay or the -omic (a label for the features).}
#'  \item{\strong{Seurat object}:}{}
#'  \item{\strong{List of matrices}:}{ A nested list of matrices \code{Y[[i]][[j]]}. 
#'  The first index \code{i} for the views. 
#'  The second index \code{j} for the groups. 
#'  Sample are stored in rows and features in columns.}
#'  }
#' @param groups ignore...
#' @return Returns an untrained \code{\link{MOFA}} object
#' @export
create_mofa <- function(data, groups = NULL) {
  
  # Creating MOFA object from a Seurat object
  if (is(data, "Seurat")) {
    
    message("Creating MOFA object from a Seurat object...")
    object <- .create_mofa_from_seurat(data, groups)
    
  # Creating MOFA object from a data.frame object
  } else if (is(data, "data.frame")) {
    
    message("Creating MOFA object from a data.frame...")
    object <- .create_mofa_from_df(data)
    
  # Creating MOFA object from a (sparse) matrix object
  } else if (is(data, "list") && (length(data) > 0) && 
             (all(sapply(data, function(x) is(x, "matrix"))) || 
              all(sapply(data, function(x) is(x, "dgCMatrix"))) || 
              all(sapply(data, function(x) is(x, "dgTMatrix"))))) {
    
    message("Creating MOFA object from a list of matrices (features as rows, sample as columns)...\n")
    object <- .create_mofa_from_matrix(data, groups)

  } else {
    stop("Error: input data has to be provided as a list of matrices, a data frame  or a Seurat object. Please read the documentation.")
  }
  
  # Do quality control on the untrained MOFA object
  # qualityControl(object)
  
  # Create sample metadata
  tmp <- data.frame(
    sample_name = unname(unlist(lapply(object@data[[1]], colnames))),
    group_name = unlist(lapply(1:object@dimensions$G, function(x) rep(groups_names(object)[[x]], object@dimensions$N[[x]]) )),
    stringsAsFactors = FALSE
  )
  samples_metadata(object) <- tmp

  # Create features metadata
  tmp <- data.frame(
    feature_name = unname(unlist(lapply(object@data, function(x) rownames(x[[1]])))),
    view_name = unlist(lapply(1:object@dimensions$M, function(x) rep(views_names(object)[[x]], object@dimensions$D[[x]]) )),
    stringsAsFactors = FALSE
  )
  features_metadata(object) <- tmp
  
  return(object)
}



# (Hidden) function to initialise a MOFA object using a Dataframe
.create_mofa_from_df <- function(df) {
  
  # Quality controls
  data <- as.data.frame(data)
  stopifnot(all(colnames(df) %in% (c("sample","feature","value","group","view"))))
  stopifnot(all(is.numeric(df$value)))
  
  # Convert 'sample' and 'feature' columns to factors
  if (!is.factor(df$sample))
    df$sample <- as.factor(df$sample)
  if (!is.factor(df$feature))
    df$feature <- as.factor(df$feature)
  
  # Convert 'group' columns to factors
  if (!"group" %in% colnames(df)) {
    df$group <- factor("group1")
  } else {
    df$group <- factor(df$group)
  }
  
  # Convert 'view' columns to factors
  if (!"view" %in% colnames(df)) {
    df$view <- factor("view1")
  } else {
    df$view <- factor(df$view)
  }
  
  data_matrix <- list()
  for (m in levels(df$view)) {
    data_matrix[[m]] <- list()
    features <- as.character( unique( df[df$view==m,"feature"] ) )
    for (g in levels(df$group)) {
      samples <- as.character( unique( df[df$group==g,"sample"] ) )
      Y <- df[df$view==m & df$group==g,]
      Y$sample <- factor(Y$sample, levels=samples)
      Y$feature <- factor(Y$feature, levels=features)
      if (nrow(Y)==0) {
        data_matrix[[m]][[g]] <- matrix(as.numeric(NA), ncol=length(samples), nrow=length(features))
        rownames(data_matrix[[m]][[g]]) <- features
        colnames(data_matrix[[m]][[g]]) <- samples
      } else {
        data_matrix[[m]][[g]] <- .df_to_matrix( reshape2::dcast(Y, feature~sample, value.var="value", fill=NA, drop=FALSE) )
      }
    }
  }
  
  # Create MOFA object
  object <- new("MOFA")
  object@status <- "untrained"
  object@data <- data_matrix
  
  # Set dimensionalities
  object@dimensions[["M"]] <- length(levels(df$view))
  object@dimensions[["D"]] <- sapply(levels(df$view), function(m) length(unique(df[df$view==m,]$feature)))
  object@dimensions[["G"]] <- length(levels(df$group))
  object@dimensions[["N"]] <- sapply(levels(df$group), function(g) length(unique(df[df$group==g,]$sample)))
  object@dimensions[["K"]] <- 0
  
  # Set view names
  views_names(object) <- levels(df$view)
  
  # Set group names
  groups_names(object) <- levels(df$group)
  
  return(object)
}

# (Hidden) function to initialise a MOFA object using a Seurat object
.create_mofa_from_seurat <- function(srt, groups, assay = "RNA") {
  if (is(groups, 'character') && (length(groups) == 1)) {
    if (!(groups %in% colnames(srt@meta.data)))
      stop(paste0(groups, " is not found in the Seurat@meta.data.\n",
                  "If you want to use groups information from Seurat@meta.data,\n",
                  "please ensure to provide a column name that exists. The columns of meta data are:\n",
                  paste0(colnames(srt@meta.data), sep = ", ")))
    groups <- srt@meta.data[,groups]
  }

  if (is.null(groups)) {
    message("No groups provided as argument... we assume that all samples are coming from the same group.\n")
    groups <- rep("group1", dim(GetAssay(object = srt, assay = assay))[2])
  }

  data_matrices <- list("rna" = .split_seurat_into_groups(srt, groups, assay))

  object <- new("MOFA")
  object@status <- "untrained"
  object@data <- data_matrices
  
  # Define dimensions
  object@dimensions[["M"]] <- 1
  object@dimensions[["D"]] <- nrow(data_matrices[[1]][[1]])
  object@dimensions[["G"]] <- length(data_matrices[[1]])
  object@dimensions[["N"]] <- sapply(data_matrices[[1]], function(m) ncol(m))
  object@dimensions[["K"]] <- 0

  # Set views & groups names
  groups_names(object) <- as.character(names(data_matrices[[1]]))
  views_names(object)  <- c("rna")

  return(object)
}


.split_data_into_groups <- function(data, groups) {
  groups_names <- unique(groups)
  tmp <- lapply(data, function(x) {
    tmp_view <- lapply(groups_names, function(p) {
      x[,groups == p]
    })
    names(tmp_view) <- groups_names
    tmp_view
  })
  names(tmp) <- names(data)
  tmp
}

# (Hidden) function to split data in Seurat object into a list of matrices
.split_seurat_into_groups <- function(srt, groups, assay = "RNA") {
  groups_names <- unique(groups)
  tmp <- lapply(groups_names, function(g) {
    # If group name is NA, it has to be treated separately
    # due to the way R handles NAs and equal signs
    if (is.na(g)) {
      GetAssayData(object = srt, assay = assay, slot = "data")[,is.na(groups)]
    } else {
      GetAssayData(object = srt, assay = assay, slot = "data")[,which(groups == g)]
    }
  })
  names(tmp) <- groups_names
  tmp
}

.df_to_matrix <- function(x) {
  m <- as.matrix(x[,-1])
  rownames(m) <- x[[1]]
  m
}

# (Hidden) function to create MOFA object from a matrix
.create_mofa_from_matrix <- function(data, groups) {
  
  # Quality controls
  stopifnot(all(sapply(data, function(g) all(is.numeric(g)))) || all(sapply(data, function(x) class(x) %in% c("dgTMatrix", "dgCMatrix"))))
  stopifnot(length(Reduce("intersect",lapply(data,colnames)))>1)
  
  # Make a dgCMatrix out of dgTMatrix
  if (all(sapply(data, function(x) is(x, "dgTMatrix")))) {
    data <- lapply(data, function(m) as(m, "dgCMatrix"))
  }
  
  # If number of rows are not identical, fill missing values
  samples <- Reduce("union",sapply(data,colnames))
  data <- sapply(data, function(x) {
    aug_x <- matrix(NA, nrow=nrow(x), ncol=length(samples))
    aug_x <- x[,match(samples,colnames(x)),drop=FALSE]
    rownames(aug_x) <- rownames(x)
    colnames(aug_x) <- samples
    return(aug_x)
  }, USE.NAMES = T, simplify = F)

  # Set groups names
  if (is.null(groups)) {
    message("No groups provided as argument... we assume that all samples are coming from the same group.\n")
    groups <- rep("group1", ncol(data[[1]]))
  }
  groups_names <- as.character(unique(groups))
  
  # Set views names
  if (is.null(names(data))) {
    default_views_names <- paste0("view_", 1:length(data))
    message(paste0("View names are not specified in the data, using default: ", paste(default_views_names, collapse=", "), "\n"))
    names(data) <- default_views_names
  }
  views_names <- as.character(names(data))
  
  # Initialise MOFA object
  object <- new("MOFA")
  object@status <- "untrained"
  object@data <- .split_data_into_groups(data, groups)
  
  # Set dimensionalities
  object@dimensions[["M"]] <- length(data)
  object@dimensions[["G"]] <- length(groups_names)
  object@dimensions[["D"]] <- sapply(data, function(m) nrow(m))
  object@dimensions[["N"]] <- sapply(groups_names, function(x) sum(groups == x))
  object@dimensions[["K"]] <- 0
  
  # Set features names
  for (m in 1:length(data)) {
    if (is.null(rownames(data[[m]]))) {
      warning(sprintf("Feature names are not specified for view %d, using default: feature1_v%d, feature2_v%d...", m, m, m))
      for (g in 1:length(object@data[[m]])) {
        rownames(object@data[[m]][[g]]) <- paste0("feature_", 1:nrow(object@data[[m]][[g]]), "_v", m)
      }
    }
  }
  
  # Set samples names
  for (g in 1:object@dimensions[["G"]]) {
    if (is.null(colnames(object@data[[1]][[g]]))) {
      warning(sprintf("Sample names for group %d are not specified, using default: sample1_g%d, sample2_g%d,...", g, g, g))
      for (m in 1:object@dimensions[["M"]]) {
        colnames(object@data[[m]][[g]]) <- paste0("sample_", 1:ncol(object@data[[m]][[g]]), "_g", g)
      }
    }
  }
  
  # Set view names
  views_names(object) <- names(object@data)
  
  # Set samples group names
  groups_names(object) <- names(object@data[[1]])
  
  return(object)
}