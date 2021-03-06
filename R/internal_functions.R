
rrt_compact <- function (l) Filter(Negate(is.null), l)

mssg <- function(x, ...) if(x) message(...)

checkUserInstall <- function(lib){
  if(file.exists(file.path(lib))){
    ss <- list.dirs(file.path(lib), recursive = FALSE, full.names = FALSE)
    haveinst <- ss[!ss %in% c("src","packrat","rstudio","manipulate","RRT")]
    # check if is a package or not
    if(!length(haveinst) == 0){
      try_aspkg <- function(x){
        tt <- tryCatch(as.package(x), error=function(e) e)
        if("error" %in% class(tt)) FALSE else TRUE
      }
      haveinst <- haveinst[vapply(file.path(lib, haveinst), try_aspkg, TRUE)]
    } else { haveinst <- character(0) }
  }
  if(file.exists(file.path(lib, "src/contrib"))){
    tt <- list.files(file.path(lib, "src/contrib"), pattern = ".tar.gz|.zip")
    havesource <- sapply(tt, function(x) strsplit(x, "_")[[1]][[1]], USE.NAMES = FALSE)
  }
  
  return(if(!length(haveinst) == 0) haveinst[!haveinst %in% havesource] else NULL)
}

#' Creates unique repo id from a digest of the file path.
#' 
#' @inheritParams checkpoint
#' 
#' @import digest
#' @keywords Internal
repoDigest <- function(repo){
  digest(normalizePath(repo, mustWork=FALSE))
}

