#' Construct a REVOLVER cohort object (S3 class \code{"rev_cohort"}).
#'
#' @param dataset A dataframe in the specified format (see Online manual).
#' @param CCF.parser A function to parse the format for the encoding of CCF
#' or binary values for each sequenced region. A possible function is available
#' inside REVOLVER; since it is not exported but is available with
#' \code{revolver:::CCF.parser} (the default of this parameter).
#' @param options A list of 2 parameters that should be a boolean value for
#' \code{ONLY.DRIVER} (use only driver SNVs), and \code{MIN.CLUSTER.SIZE}, the minimum cluster size.
#' @param annotation String for annotation of this cohort. This will be prompted
#'                   in every print for this object.
#'
#' @return An object of class \code{"rev_cohort"}
#'
#' @aliases revolver_cohort
#'
#' @examples
#' data(CRC)
#' cohort = revolver_cohort(CRC, options = list(ONLY.DRIVER = FALSE, MIN.CLUSTER.SIZE = 0))
#'
#' @import crayon
#'
#' @export
revolver_cohort = function(
  dataset,
  CCF.parser = revolver:::CCF.parser,
  options = list(ONLY.DRIVER = FALSE, MIN.CLUSTER.SIZE = 10),
  annotation = '')
{
  REVOLVER_VERSION = revolver_version()$REVOLVER_VERSION

  # xx = lapply(revolver:::revolver_version(), cat)

  # Dataset with certain columns
  required.cols = c('Misc', 'patientID', 'variantID',  'cluster', 'is.driver', 'is.clonal', 'CCF')
  if(!all(required.cols %in% colnames(dataset)))
    stop('Dataset should have the following columns:', paste(required.cols, collapse = ', '))

  if(!is.function(CCF.parser))
     stop('You need to provide a function to parse CCFs, check "CCF.parser".')

  pio::pioHdr(
    paste('REVOLVER Cohort Constructor for version', REVOLVER_VERSION),
    c(
      `Use only alterations annotated as driver` = options$ONLY.DRIVER,
      `Filter: minimum number of alterations in a group/ cluster` = options$MIN.CLUSTER.SIZE
    ),
    prefix = '\t')

  dataset = dataset[, required.cols]

  if(options$ONLY.DRIVER)
  {
    dataset = dataset[dataset$is.driver, , drop = FALSE]
  }

  pio::pioTit('Input data')
  pio::pioDisp(dataset)

  if(options$MIN.CLUSTER.SIZE > 0){

    pio::pioTit('Checking size of groups/ clusters')

    cat('Rows before filtering:', nrow(dataset), '\n\n')

    data.split = split(dataset, f = dataset$patientID)

    data.reduced = lapply(
      seq(data.split),
      function(p){
        patient = names(data.split)[p]
        p = data.split[[p]]

        p = filter.clusters(p, cutoff.numMuts = options$MIN.CLUSTER.SIZE)

        if(!is.null(p$removed))
        {
          message('\nRemoved from ', patient)
          pio::pioDisp(p$removed)
        }

        p$remained
      })

    dataset = Reduce(rbind, data.reduced)
    cat('\nRows after filtering:', nrow(dataset), '\n')
  }

  pio::pioTit('Extracting CCF values')
  data = split(dataset, f = dataset$patientID)
  dataset.expanded = lapply(data, function(x) {

    samples = names(CCF.parser(x[1, 'CCF']))

    CCF.values = lapply(x$CCF, CCF.parser)
    CCF.values = Reduce(rbind, CCF.values)

    if(nrow(x) == 1) CCF.values = t(as.data.frame(CCF.values))
    CCF.values = apply(CCF.values, 2, as.numeric)
    if(nrow(x) == 1) CCF.values = t(as.data.frame(CCF.values))

    rownames(CCF.values) = rownames(x)
    cbind(x, CCF.values)
    # clusters.table(x, samples)
  })
  names(dataset.expanded) = names(data)

  CCF =  lapply(dataset.expanded, function(x) {
    clusters.table(x,
                   names(CCF.parser(x[1, 'CCF'])))
  })

  patients = unique(dataset$patientID)
  variantIDs = unique(dataset$variantID)
  variantIDs.driver = unique(dataset[dataset$is.driver, 'variantID'])

  numVariants = nrow(dataset)

  n = list(
    patients = length(patients),
    variants = nrow(dataset),
    drivers = length(dataset[dataset$is.driver, 'variantID'])
  )

  obj <-
    structure(
      list(
        patients = patients,
        variantIDs = variantIDs,
        variantIDs.driver = variantIDs.driver,
        numVariants = numVariants,
        annotation = annotation,
        dataset = dataset,
        data = data,
        CCF = CCF,
        n = n,
        CCF.parser = CCF.parser,
        REVOLVER_VERSION = REVOLVER_VERSION
      ),
      class = "rev_cohort",
      call = match.call()
    )

  return(obj)
}


#' Print a \code{"rev_cohort"} object
#'
#' @param x obj of class \code{"rev_cohort"}
#' @param digits number of output digits
#'
#' @return nothing
#' @export print.rev_cohort
#' @import crayon
#'
#' @examples
#' data(CRC.cohort)
#' CRC.cohort
print.rev_cohort <- function(x, digits = max(3, getOption("digits") - 3), ...)
{
  stopifnot(inherits(x, "rev_cohort"))

  pio::pioHdr(paste('REVOLVER ', x$REVOLVER_VERSION), toPrint = NULL)

  # cat(bgCyan('REVOLVER'), cyan(x$REVOLVER_VERSION))
  # cat(blue(paste(' -- ', x$annotation, sep ='')), '\n')

  cat('\n\t', blue(x$annotation, sep =''), '\n')
  cat('\n\t', cyan('Patient IDs     :'), paste(head(x$patients), collape =', ', sep =''), '...')
  cat('\n\t', cyan('Cohort size     :'), length(x$patients), 'patients,', x$numVariants, 'alterations,', length(x$variantIDs.driver), 'drivers')
  cat('\n\t', cyan('Drivers         :'), paste(head(x$variantIDs.driver), collape =', ', sep =''), '... \n')

  pio::pioTit('Computations available', prefix = '\t')

  cat('\n\t', cyan('Trees per patient    :'),
      ifelse(is.null(x$phylogenies), red('NO'), green('YES')))

  cat('\n\t', cyan('Fit via TL           :'),
      ifelse(is.null(x$fit), red('NO'), green('YES')))

  cat('\n\t', cyan('REVOLVER clustering  :'),
      ifelse(is.null(x$cluster), red('NO'), green('YES')))

  cat('\n\t', cyan('Jackknife statistics :'),
      ifelse(is.null(x$jackknife), red('NO'), green('YES')))

  cat('\n')

  if(!is.null(x$phylogenies))
  {
    pio::pioTit('Summary for data and models', prefix = '\t')

    # cat(cyan('\n\tTL Model Fit  :'), ifelse(is.null(x$fit), red('NO\n'), green('YES ')), '\n')

    longest.name = max(nchar(names(x$phylogenies)))

    patf = function(w, fit, clusters) {

      patient = names(x$phylogenies)[w]

      s = paste(
        yellow(sprintf(paste('%', longest.name, 's', sep = ''), patient)),  ': ',
          sprintf('k = %3s | t = %3s | n = %2s | r = %2s | m = %4s | d = %2s',
                  length(x$phylogenies[[w]]),
                  rev_count_information_transfer_comb(x, names(x$phylogenies)[w]),
                  x$phylogenies[[w]][[1]]$numNodes,
                  x$phylogenies[[w]][[1]]$numRegions,
                  nrow(x$phylogenies[[w]][[1]]$dataset),
                  nrow(x$phylogenies[[w]][[1]]$dataset[x$phylogenies[[w]][[1]]$dataset$is.driver, ])
          ),  '\t')

      cat('\t', s)

      if(fit)
      {
        stas = stats.rev_phylo(x$fit$phylogenies[[w]])

        rank = x$fit$solutionID[w]
        score = format(x$fit$phylogenies[[w]]$score, scientific = TRUE, digits = 2)
        gofit = format(stas$gofit, scientific = TRUE, digits = 2)

        cat(
          bgBlue('[ Fit ]', sprintf(' # %3s', yellow(rank)), ' '),
          '| g =', red(sprintf('%8s', gofit)),
          '| f =', green(sprintf('%8s', score)), '  '
          )
      }

      if(clusters)
      {
        cluster = x$cluster$clusters[patient]

        cat(bgMagenta('[ Cluster', sprintf('%3s', yellow(cluster)), ']'))

      }

      cat('\n')
    }

    cat('\n')
    sapply(1:length(x$phylogenies), patf, fit = !is.null(x$fit), cluster = !is.null(x$cluster))


    cat('\n\tLegend \n\t\t k : phylogenies  \n\t\t t : combinations of information transfer \n\t\t n : groups (nodes of the tree) \n\t\t r : regions (inputs per patient) \n\t\t m : number of alterations \n\t\t d : number of driver alterations\n')

    if(!is.null(x$fit))
      cat('\t\t # : number of the solution selection (out of k)  \n\t\t g : goodness-of-fit \n\t\t f : score of the model\n')

    if(!is.null(x$cluster))
    {
      pio::pioTit('Summary for clusters', prefix = '\t')

      ids = names(x$cluster$labels.colors)

      medians = rep(NA, length(ids))

      if(!is.null(x$jackknife)) {
        medians = x$jackknife$cluster.medians
      }

      size = as.vector(table(x$cluster$clusters))

      df = data.frame(Cluster = ids, n = size, Jackknife = medians)
      apply(df, 1, function(w){

        cat(
          '\n\t',
          paste(yellow(sprintf('%4s', w['Cluster'])),  ': ',
          sprintf('n = %4s | jackknife = %4s',
                  w['n'],
                  w['Jackknife'])
          ))

      })

      cat('\n\n\tLegend \n\t\t         n : number of patients in the cluster')

      if(!is.null(x$jackknife))
        cat('\n\t\t jackknife : median co-clustering probability estiamted with jackknife\n')

      # assignments = x$cluster$clusters
      # edges = x$jackknife$edges
      # pio::pioTit('Summary for edges', prefix = '\t')
      # colnames(edges)[3] = 'Jackknife'
      # pio::pioDisp(edges)
    }
  }

  cat('\n')
  revolver_check_cohort(x)

}



#' @title Compute/ add CCF-based phylogenies to a REVOLVER cohort.
#'
#' @details
#'
#' Create or compute phylogenies for REVOLVER fit from CCF data. This method should be used also if one
#' has already pre-computed trees to use for fitting.
#'
#' @param x An object of class \code{"rev_cohort"}
#' @param patient A patient in the cohort, for which phylogenies are created
#' @param precomputed.trees If a list a of precomputed trees is available, this list should contain their
#' adjacency matrix. No computation will be carried out in this case.
#' @param precomputed.scores If a list a of precomputed trees is available, this list should contain their
#' scores. No computation will be carried out in this case.
#' @param options If one wants to generate new phylogenies for this patient, there named parameters should be
#' passed through this list. \code{sspace.cutoff = 10000} is the state-space cutoff to generate trees in an
#' exhaustive fashion, or to Montecarlo sample them. If Montecarlo is chosen \code{sampling} tells how
#' many trees are sampled. \code{overwrite = FALSE} sets if the patient's current phylogenies
#' should be overwritten, in case they are already available. \code{store.max = 100} tells how many trees should
#' be stored, if there are more than \code{store.max} available (ranked).
#' @param verbose output type.
#'
#' @return a modififed object of class \code{"rev_cohort"} with available phylogeneis for \code{patient}.
#' @export
#' @import crayon
#'
#' @examples
#' \dontrun{
#'  TODO
#' }
#'
revolver_compute_phylogenies = function(
  x,
  patient,
  precomputed.trees = NULL,
  precomputed.scores = NULL,
  options = list(sspace.cutoff = 10000,
                 n.sampling = 5000,
                 overwrite = FALSE,
                 store.max = 100),
  verbose = FALSE
  )
{
  Original.dataset = x$dataset
  use.MI = FALSE

  # Prepare output
  if(is.null(x$phylogenies)) x$phylogenies = NULL


  pio::pioHdr(paste("REVOLVER Construct phylogenetic trees for", patient),
              c(
                `Use precomputed trees` = paste(all(!is.null(precomputed.trees))),
                `Maximum state space size to switch from exhaustive to Montecarlo search` = options$sspace.cutoff,
                `Number of Montecarlo samples, if not exhaustive` = options$n.sampling,
                `Overwrite the tree if it is already available` = options$overwrite,
                `Maximumum number of trees to store, if multiple are available` = options$store.max
              ),
              prefix = '\t'
              )

  if(!is.null(x$phylogenies))
  {
    if(patient %in% names(x$phylogenies))
    {
      if(!as.logical(options['overwrite']))
      {
        cat(red('\nModels already available and overwrite is FALSE -- skipping patient.\n'))
        return(x)
      }
    }
  }
  cat('\n')


  x$dataset = x$dataset[x$dataset$patientID  == patient, ]

  samples = names(x$CCF.parser(x$dataset[1, 'CCF']))

  CCF = sapply(x$dataset$CCF, x$CCF.parser)
  if(length(samples) == 1) {
    CCF = matrix(CCF, ncol = 1)
    colnames(CCF) = samples
  } else CCF = t(CCF)

  CCF = apply(CCF, 2, as.numeric)
  rownames(CCF) = rownames(x$dataset)

  x$dataset = x$dataset[, c('Misc', 'patientID', 'variantID', 'cluster', 'is.driver', 'is.clonal')]
  x$dataset = cbind(x$dataset, CCF)

  if(verbose) print(head(x$dataset))

  # cat(cyan('[compute_rev_phylogenies] Clusters for this patient ... \n'))
  clusters = revolver:::clusters.table(x$dataset, samples)
  nclusters = nrow(clusters)

  TREES = SCORES = NULL

  if(!any(is.null(precomputed.trees))){
    cat(yellow('\n\nPrecomputed trees given as input ... using them.\n\n'))

    TREES = precomputed.trees
    SCORES = precomputed.scores
  }
  else
  {
    pio::pioTit("Groups/ Clusters in the data of this patient")
    print(clusters)

    if(nclusters == 1)
    {
      cat(red('\nThis model has 1 node, it has trivial models.'))

      M = matrix(0, ncol = 1, nrow = 1)
      colnames(M) = rownames(M) = rownames(clusters)

      TREES = append(TREES, list(M))
      SCORES = c(SCORES, 1)
    }
    else
    {
      # ################## Generate all trees that are compatible with the observed CCFs, we do this
      # ################## by analyzing one sample at a time.
      pio::pioTit("Using ClonEvol to build phylogentic trees, per region (this might take some time)")

      clonal.cluster = as.character(unique(x$dataset$cluster[x$dataset$is.clonal]))

      # December 2018 - https://github.com/caravagn/revolver/issues/13
      #
      # Original code which would run ClonEvol's functions
      #
      # x$dataset[, samples] =  x$dataset[, samples] * 100
      # clonevol.obj = revolver:::useClonevo(x$dataset, samples, clonal.cluster)
      # x$dataset[, samples] =  x$dataset[, samples] / 100
      #
      # Alternative implementation of ClonEvol's steps that we use. We use our function
      # and reacreate an obj matching the expected output, so we do not need
      # to update downstream functions.
      alternative = NULL
      alternative$models = ClonEvol_surrogate(clusters, samples, clonal.cluster, min.CCF = 0.01)
      clonevol.obj = alternative

      # remove the trees which have no edges (returned for samples with only 1 cluster for instance)
      numSol = sapply(clonevol.obj$models, function(w){ sum(sapply(w, nrow) > 0) })
      pio::pioDisp(data.frame(region = names(clonevol.obj$models), Solutions = numSol))

      ################## Build all possible clonal trees
      # 1) hash them
      # 2) create a consensus as the union of all trees
      # 3) generate or sample a large number of possible trees, where a parent x --> y is assigned
      #    with probability proportional to how often the edge is detected

      pio::pioTit("Hashing, merging and generating solutions (this might take some time)")
      CLONAL.TREES = revolver:::hashTrees(clonevol.obj, samples)

      CONSENSUS = revolver:::consensusModel(clonevol.obj, samples)
      CONSENSUS.TREE = CONSENSUS$S
      WEIGHTS.CONSENSUS.TREE = CONSENSUS$weights

      cat("Created graph of all possible ancestries\n")

      # # Sampling is carried out if there are more than 'sspace.cutoff' trees, in that case we
      # # sample 'n.sampling' possible trees. Otherwise all possible trees are generated.
      TREES = revolver:::all.possible.trees(
        CONSENSUS.TREE,
        WEIGHTS.CONSENSUS.TREE,
        sspace.cutoff = options['sspace.cutoff'],
        n.sampling = options['n.sampling']
      )

      pio::pioTit("Scoring and ranking solutions (this might take some time)")

      # ################## Ranking trees. A tree is good according to the following factors:
      # # 1) the MI among the variables x and y, if they are connected by an edge x --> y [TODO: consider if we really need MI]
      # # 2) the Multinomial probability of edge x --> y in the trees determined by the CCF
      # # 3) for every edge  x --> y, the number of times that the CCF of x is greater than the CCF of y
      # # 3) for every node  x --> y1 ... yK, the number of times that the CCF of x is greater than the sum of the CCFs of y1 ... yK
      binary.data = revolver:::binarize(x$dataset, samples)

      # 1) MI from binarized data -- different options, with a control sample which avoids 0log(0)
      # • a=0:maximum likelihood estimator (see entropy.empirical)
      # • a=1/2:Jeffreys’ prior; Krichevsky-Trovimov (1991) entropy estimator
      # • a=1:Laplace’s prior
      # • a=1/length(y):Schurmann-Grassberger (1996) entropy estimator
      # • a=sqrt(sum(y))/length(y):minimax prior
      MI.table = revolver:::computeMI.table(binary.data, MI.Bayesian.prior = 0, add.control = TRUE)
      if(!use.MI) MI.table[TRUE] = 1

      # Steps 1 and 2 are collapsed, multiply MI by the Multinomial probability
      MI.table = revolver:::weightMI.byMultinomial(MI.table, WEIGHTS.CONSENSUS.TREE)

      # 3) Get penalty for direction given CCFs -- this is done for all possible edges in the data
      CCF = clusters[, samples, drop = FALSE]
      # penalty.CCF.direction = edge.penalty.for.direction(TREES, CCF)
      penalty.CCF.direction = 1

      # 4) Compute the branching penalty  --  this is done for each tree that we are considering
      cat('Computing Pigeonhole Principle\n')
      penalty.CCF.branching = revolver:::node.penalty.for.branching(TREES, CCF)

      cat('Computing rank\n')
      RANKED = revolver:::rankTrees(TREES, MI.table, penalty.CCF.branching)
      TREES = RANKED$TREES
      SCORES = RANKED$SCORES

      TREES = TREES[SCORES > 0]
      SCORES = SCORES[SCORES > 0]
    }
  }

  if(length(TREES) == 0){
    cat(red('No phylogenies found for this patient -- check data? -- returning original cohort.\n'))

    x$dataset = Original.dataset
    return(x)
  }

  pio::pioTit("Creating rev_phylo object for REVOLVER (this might take some time)")

  x$phylogenies[[patient]] = create_trees_in_revolver_format(options, TREES, SCORES, patient, x$dataset, samples)

  # Restore data
  x$dataset = Original.dataset

  comb = rev_count_information_transfer_comb(x, patient)
  pio::pioStr('\n Combinations of Information Transfer : ', crayon::yellow(comb), suffix = '\n')

  return(x)
}

#' @title Compute/ add mutation trees to a REVOLVER cohort.
#'
#' @details
#' This is the analogous of \code{\link{revolver_compute_phylogenies}}, but for binary data and
#' hence it computes Chow-Liu trees using also Suppes' conditions. Parameters have exactly
#' the same meaning of the ones described in \code{\link{revolver_compute_phylogenies}}.
#'
#' @param x An object of class \code{"rev_cohort"}
#' @param patient A patient in the cohort, for which mutation trees are created
#' @param precomputed.trees See \code{\link{revolver_compute_phylogenies}}
#' @param precomputed.scores See \code{\link{revolver_compute_phylogenies}}
#' @param options See \code{\link{revolver_compute_phylogenies}}.
#' @param verbose output type.
#'
#' @return a modififed object of class \code{"rev_cohort"} with available
#' mutation trees for \code{patient}.
#' @export
#' @import crayon
#'
#' @examples
#' data(CRC.cohort)
#' new.cohort = revolver_compute_CLtrees(CRC.cohort, patient = 'adenoma_1')
#' print(new.cohort$phylogenies$adenoma_1)
revolver_compute_CLtrees = function(
  x,
  patient,
  precomputed.trees = NULL,
  precomputed.scores = NULL,
  options = list(sspace.cutoff = 10000,
                 n.sampling = 5000,
                 overwrite = FALSE,
                 store.max = 100),
  verbose = FALSE
)
{
  Original.dataset = x$dataset

  # Prepare output
  if(is.null(x$phylogenies)) x$phylogenies = NULL

  pio::pioHdr(paste("REVOLVER Construct mutational trees (Chow-Liu) for", patient),
              c(
                `Use precomputed trees` = paste(all(!is.null(precomputed.trees))),
                `Maximum state space size to switch from exhaustive to Montecarlo search` = options$sspace.cutoff,
                `Number of Montecarlo samples, if not exhaustive` = options$n.sampling,
                `Overwrite the tree if it is already available` = options$overwrite,
                `Maximumum number of trees to store, if multiple are available` = options$store.max
              ),
              prefix = '\t'
  )

  if(!is.null(x$phylogenies))
  {
    if(patient %in% names(x$phylogenies))
    {
      if(!as.logical(options['overwrite']))
      {
        cat(red('\nModels already available and overwrite is FALSE -- skipping patient.\n'))
        return(x)
      }
    }
  }
  cat('\n')


  # Phylo creation
  x$dataset = x$dataset[x$dataset$patientID  == patient, ]

  samples = names(x$CCF.parser(x$dataset[1, 'CCF']))

  CCF = sapply(x$dataset$CCF, x$CCF.parser)

  if(length(samples) == 1) {
    CCF = matrix(CCF, ncol = 1)
    colnames(CCF) = samples
  } else CCF = t(CCF)

  CCF = apply(CCF, 2, as.numeric)

  if(nrow(x$dataset) == 1) {
    CCF = matrix(CCF, nrow = nrow(x$dataset), ncol = length(samples))
    colnames(CCF) = samples
  }

  rownames(CCF) = rownames(x$dataset)

  x$dataset = x$dataset[, c('Misc', 'patientID', 'variantID', 'cluster', 'is.driver', 'is.clonal')]
  x$dataset = cbind(x$dataset, CCF)

  if(verbose) print(head(x$dataset))

  clusters = clusters.table(x$dataset, samples)
  nclusters = nrow(clusters)

  TREES = SCORES = NULL
  if(!any(is.null(precomputed.trees))){
    cat(yellow('\nPrecomputed trees given as input ... using them.\n'))

    TREES = precomputed.trees
    SCORES = precomputed.scores
  }
  else
  {
    pio::pioTit("Groups/ Clusters in the data of this patient")
    print(clusters)

    if(nclusters == 1)
    {
      cat(red('\nThis model has 1 node, we cannot compute its score.'))

      M = matrix(0, ncol = 1, nrow = 1)
      colnames(M) = rownames(M) = rownames(clusters)

      TREES = append(TREES, list(M))
      SCORES = c(SCORES, 1)
    }
    else
    {
      pio::pioTit("Computing Suppes' extended poset")

      ################### Generate Suppes poset
      POSET = poset(x = clusters, regions = samples)

      # we transform it in the input for the tree sampler
      POSET = lapply(POSET, function(w)
      {
        n = names(w)
        w = as.numeric(w)/length(w)
        names(w) = n
        w
      })

      POSET.EDGES = lapply(POSET, names)
      POSET.EDGES = lapply(names(POSET.EDGES), function(w){
        expand.grid(from = POSET.EDGES[[w]], to = w, stringsAsFactors = FALSE)
      })
      POSET.EDGES = Reduce(rbind, POSET.EDGES)

      pio::pioDisp(POSET.EDGES)

      # # Sampling is carried out if there are more than 'sspace.cutoff' trees, in that case we
      # # sample 'n.sampling' possible trees. Otherwise all possible trees are generated.
      # cat(cyan('[compute_rev_phylogenies] Generating possible solutions (it might take time) ... \n'))

      pio::pioTit("Computing solutions from poset (this might take some time)")

      TREES = all.possible.trees(
        G = POSET.EDGES,
        W = POSET,
        sspace.cutoff = options['sspace.cutoff'],
        n.sampling = options['n.sampling']
      )

      pio::pioTit("Scoring and ranking solutions (this might take some time)")

      # ################## Ranking trees. A tree is good according to the following factors:
      # # 1) the MI among the variables x and y, if they are connected by an edge x --> y [TODO: consider if we really need MI]
      # # 2) the Multinomial probability of edge x --> y in the trees determined by the CCF
      # # 3) for every edge  x --> y, the number of times that the CCF of x is greater than the CCF of y
      # # 3) for every node  x --> y1 ... yK, the number of times that the CCF of x is greater than the sum of the CCFs of y1 ... yK
      binary.data = binarize(x$dataset, samples)

      # 1) MI from binarized data -- different options, with a control sample which avoids 0log(0)
      # • a=0:maximum likelihood estimator (see entropy.empirical)
      # • a=1/2:Jeffreys’ prior; Krichevsky-Trovimov (1991) entropy estimator
      # • a=1:Laplace’s prior
      # • a=1/length(y):Schurmann-Grassberger (1996) entropy estimator
      # • a=sqrt(sum(y))/length(y):minimax prior
      cat('Computing Mutual Information from data\n')
      MI.table = computeMI.table(binary.data, MI.Bayesian.prior = 0, add.control = TRUE)

      pio::pioDisp(MI.table)

      cat('Computing rank\n')
      RANKED = rankTrees(TREES, MI.table, structural.score = NULL)
      TREES = RANKED$TREES
      SCORES = RANKED$SCORES

      TREES = TREES[SCORES > 0]
      SCORES = SCORES[SCORES > 0]
    }
  }

  if(length(TREES) == 0){
    cat(red('No trees found for this patient -- check data? -- returning original cohort.\n'))

    x$dataset = Original.dataset
    return(x)
  }

  pio::pioTit("Creating rev_phylo objects for REVOLVER (this might take some time)")

  x$phylogenies[[patient]] = create_trees_in_revolver_format(options, TREES, SCORES, patient, x$dataset, samples)

  # Restore data
  x$dataset = Original.dataset

  return(x)
}



#' @title Check basic inconsistencies in a REVOLVER cohort.
#'
#' @details Perform some basic diagnostic of a cohort object. It will inform of patients without drivers and other
#' information that can be used to reshape the data before fitting a model.
#'
#' @param x An object of class \code{"rev_cohort"}
#' @param auto.fix Unused parameter; ideally we will implement some automatic fixing one day.
#' @param return.value If the method should return or not a report with the errors. By default is just prints to screen
#'
#' @return depends on \code{return.value}
#' @import crayon
#' @export
#'
#' @examples
#' data(CRC.cohort)
#' revolver_check_cohort(CRC.cohort)
#' print(CRC.cohort) # calls this anyway
revolver_check_cohort = function(x, auto.fix = FALSE, return.value = FALSE)
{
  # check for duplicated IDs ... parallel evolution events
  data = split(x$dataset, f = x$dataset$patientID)

  err = FALSE
  xx = lapply(
    split(x$dataset, f = x$dataset$patientID),
    function(w)
    {
      df = w[w$is.driver, ]
      mask = duplicated(df$variantID)

      if(any(mask))
      {
        cat(bgRed('\n CHECK '), red("Duplicated driver variantID in patient: "), yellow(df$patientID[1]), ':', df$variantID[mask], '\n')
        entries = df[df$variantID %in% df$variantID[mask], ]

        err = TRUE

        print(entries)
        return(entries)
      }
    })

  # Check for variants cocurring <= 1 times
  data.split = x$dataset[x$dataset$is.driver, ]
  data.split = split(data.split, f = data.split$variantID)

  occurrencesCount = lapply(data.split, function(x) nrow(x) <= 1)
  if(any(unlist(occurrencesCount))) {
    cat(bgRed('\n CHECK '), red("These drivers occurr once, will not be correlated: "))
    occurrencesCount = occurrencesCount[unlist(occurrencesCount)]

    err = TRUE

    cat(paste(names(occurrencesCount), collapse = ', '))
    # for(o in names(occurrencesCount)) {
    #   cat(yellow(o), '@', data.split[[o]][1, 'patientID'], ' | ')
    #
    #   # if(auto.fix) {
    #   #   cat(green('AUTOFIX [= TRUE] will delete it.'))
    #   #   df = data.split[[o]]
    #   #
    #   #   x = revolver_remove.driver(x,  df['patientID'], df['variantID'], df['Misc'], df['cluster'])
    #   #
    #   # }
    # }
    # cat('\n')
  }

  # check for patients with no variants
  data.split = split(x$dataset, f = x$dataset$patientID)
  data.split = lapply(data.split, function(w) w[w$is.driver, ])

  zoesp = lapply(data.split, function(w) nrow(w) == 0)
  unoesp = lapply(data.split, function(w) nrow(w) == 1)

  if(any(unlist(zoesp))) {
    cat(bgRed('\n CHECK '), red("Patients with 0 drivers are useless and should be removed:"), paste(names(zoesp)[unlist(zoesp)], collapse = ', '))

    err = TRUE
  }

  if(any(unlist(unoesp)))
    cat(bgRed('\n CHECK '), red("Patients with 1 drivers can only be expanded:"), paste(names(unoesp)[unlist(unoesp)], collapse = ', '))


  # if(any(unlist(occurrencesCount))) stop('Errors should be fixed.')

  # return(x)

  # if(auto.fix)
  # {
  #   cat(green('\nAUTOFIX running on these entries.\n'))
  #   print(Reduce(rbind, xx))
  #
  #   for(i in 1:length(xx)){
  #   }
  # }

 if(return.value) return(err)
}

#' @title Remove a driver event from a cohort.
#'
#' @details Basic editing function. Each event is identied through its ID,
#' cluster assignment and its misc flag. With this function, you can remove it.
#' The event is not physically removed from the dataset, but instead its flag
#' \code{is.Driver} is set to \code{FALSE}. If there are phylogenies inside, they are updated
#' as well. If you have fit the models, however, you should re-run the fit after this
#' modification because this modification does not propagate.
#'
#' @param x An object of class \code{"rev_cohort"}
#' @param patient Patient ID.
#' @param variantID ID of the event to mark as \code{FALSE}.
#' @param misc misc of the event to mark as \code{FALSE}
#' @param cluster cluster of the event to mark as \code{FALSE}
#'
#' @return a modified cohort object of class \code{"rev_cohort"}
#' @import crayon
#' @export
#'
#' @examples
#' data(CRC.cohort)
#' head(CRC.cohort$dataset) # Info to use to remove
#' new.data = revolver_removeDriver(CRC.cohort, "adenoma_1", "APC", "NOTHING", "1")
#' head(new.data$dataset)
revolver_removeDriver = function(
  x,
  patient,
  variantID,
  misc,
  cluster)
{
  pio::pioHdr('REVOLVER remove driver across all samples',
              toPrint = c(
                `Patient` = patient,
                `Alteration ID` = variantID,
                `Misc` = misc,
                `Group/ cluster` = cluster
              ),
              prefix = '\t -')

  x$dataset[
    x$dataset$is.driver &
      x$dataset$patientID == patient &
      x$dataset$Misc == misc &
      x$dataset$cluster == cluster, 'is.driver'
  ] = FALSE

  if(!is.null(x$phylogenies)){
    for(p in names(x$phylogenies)){
      for(model in 1: length(x$phylogenies[[p]])) {
        x$phylogenies[[p]][[model]]$dataset[
          x$dataset$is.driver &
            x$dataset$patientID == patient &
            x$dataset$Misc == misc &
            x$dataset$cluster == cluster, 'is.driver'
          ] = FALSE
      }
    }

  }



  return(x)
}


#' Subset the drivers in the cohort to match the input list.
#'
#' @param cohort An object of class \code{"rev_cohort"}
#' @param list A vector of driver IDs to subset the data to.
#'
#' @return A REVOLVER cohort with only drivers in \code{list}.
#' @export
#'
#' @examples
#' data(CRC.cohort)
#' revolver_subsetDrivers(CRC.cohort, 'APC')
revolver_subsetDrivers = function(cohort, list)
{
  pio::pioHdr('REVOLVER subsetting drivers according to list',
              toPrint = c(
                `Drivers to keep` = paste(list, collapse = ', ')
              ),
              prefix = '\t -')

  current.drivers = rownames(clonal.subclonal.table(cohort))
  toDelete = setdiff(current.drivers, list)

  cat(cyan('Removing:'), paste(toDelete, collapse = ', '))

  cohort$dataset[cohort$dataset$variantID %in% toDelete, 'is.driver'] = FALSE
  cohort$variantIDs.driver = unique(cohort$dataset[cohort$dataset$is.driver, 'variantID'])

  if(!is.null(cohort$phylogenies))
  {
    pio::pioTit("Propagating modification across trees stored in the cohort")

    # remove the driver even from the local copy of the data
    for(p in names(cohort$phylogenies))
    {
      for(f in 1:length(cohort$phylogenies[[p]]))
      {
        cohort$phylogenies[[p]][[f]]$dataset[
          cohort$phylogenies[[p]][[f]]$dataset$variantID %in% toDelete, 'is.driver'
        ] = FALSE

        # re-compute the information transfer
        cohort$phylogenies[[p]][[f]]$transfer = information.transfer(cohort$phylogenies[[p]][[f]])
      }
    }

  }

  # cat(cyan('\nChecking cohort.\n'))
  revolver_check_cohort(cohort)

  return(cohort)
}



#' Subset the patients in the cohort to match the input list.
#'
#' @param cohort An object of class \code{"rev_cohort"}
#' @param list A vector of patient IDs to subset the data to.
#'
#' @return A REVOLVER cohort with only patients in the \code{list}.
#' @export
#'
#' @examples
#' data(CRC.cohort)
#' CRC.cohort
#' revolver_deletePatients(CRC.cohort, "adenoma_2")
revolver_deletePatients = function(x, list)
{
  pio::pioHdr('REVOLVER subsetting patients according to list',
              toPrint = c(
                `Patients to keep` = paste(list, collapse = ', ')
              ),
              prefix = '\t -')

  new.patients = setdiff(x$patients, list)
  x$dataset = x$dataset[x$dataset$patientID %in% new.patients, , drop = FALSE]
  x$patients = new.patients

  if(!is.null(x$phylogenies))
    x$phylogenies = x$phylogenies[intersect(new.patients, names(x$phylogenies))]

  cat(cyan('\nChecking cohort.\n'))
  revolver_check_cohort(x)


  return(x)
}


#' @title Plot data and trees for a REVOLVER cohort.
#'
#' @details
#' Iterative plotting functions that scans a cohort and runs \code{\link{revolver_report_patient}}
#' on a set of patients (default all).
#'
#' @param x An object of class \code{"rev_cohort"}.
#' @param patients The patients to plot, default is all the one available.
#' @param max.phylogenies How many trees should be computed for each patient.
#' @param cex Scale cex for graphics.
#'
#' @return nothing
#' @export plot.rev_cohort
#' @import crayon
#'
#' @examples
#' data(Breast.fit)
#' plot.rev_cohort(Breast.fit, patients = Breast.fit$patients[1:10])
plot.rev_cohort = function(x,
                           patients = x$patients,
                           max.phylogenies = 12,
                           cex = 1)
{
  obj_has_trees(x)
  plot.stat = TRUE

  pio::pioHdr('REVOLVER Plot: Cohort (models)',
              c(
                `Patients`=paste(patients, collapse = ', '),
                `Number of trees per patient`=max.phylogenies),
              prefix = '\t -')

  if(is.na(file)) stop('A file is required for this plot!')

  for (patient in patients)
  {
    pio::pioTit(paste("Processing", patient))

    revolver_report_patient(x, patient, cex = cex, max.phylogenies = max.phylogenies)
  }
}


