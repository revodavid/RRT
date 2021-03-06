# get mran_server url, if none found, defaults to global url: http://mran.revolutionanalytics.com
mranServerUrl <- function(){
  x <- Sys.getenv('MRAN_SERVER')
  if(identical(x, "")) 'http://mran.revolutionanalytics.com' else x
}



#' Get available snapshots from MRAN
#' 
#' @inheritParams checkpoint
#'
#' @import httr XML
#' @export
#' @family mran
#' @examples \dontrun{
#' # List all available snapshots
#' mranSnapshots()
#' # Get code for a single snapshot
#' mranSnapshots(date='2014-08-04')
#' }

mranSnapshots <- function(snapshotdate=NULL, verbose=TRUE){
  url <- file.path(mranServerUrl(), 'snapshots/src')
  res <- GET(url)
  if(res$status_code > 202)
    stop(sprintf("%s - You don't have an internet connection, or other error...", res$status_code))
  text <- content(res, as = "text")
  snaps <- xpathSApply(htmlParse(text), "//a", xmlValue)[-1]
  snaps <- gsub("/", "", snaps)
  if(!is.null(snapshotdate)) snaps <- snaps[grep(snapshotdate, snaps)]
  mssg(verbose, "Dates and times are in GMT")
  return( snaps )
}

#' Get available diffs from MRAN
#'
#' @import httr XML
#' @export
#' @family mran
#' @param diff Optional. (character) A diff date-time stamp of a MRAN diff.
#' @param which (character) One of src (for source packages) or bin (for binary packages).
#' @param os (character) Operating system. One of macosx, windows, or linux.
#' @examples \dontrun{
#' mran_diffs()
#' mran_diffs(which='bin')
#' mran_diffs(which='bin', os='windows')
#' mran_diffs(which='bin', os='linux')
#'
#' # An individual diff
#' mran_diffs(diff="2014-08-01_0500")
#'
#' diffs <- mran_diffs()
#' mran_diffs(diffs[length(diffs)-1])
#' }

mran_diffs <- function(diff=NULL, which='src', os='macosx')
{
  url <- mranServerUrl()
  which <- match.arg(which, c('src','bin'))
  url <- if(which=='src') file.path(url, sprintf('diffs/%s/2014', which)) else file.path(url, sprintf('diffs/%s/%s/2014', which, os))
  if(!is.null(diff)){
    url <- sprintf('%s/%s.txt', url, diff)
  }
  res <- GET(url)
  if(res$status_code > 202)
    stop(sprintf("%s - You don't have an internet connection, or other error...", res$status_code))
  text <- content(res, as = "text")
  
  message("Dates and times are in GMT")
  
  if(is.null(diff)){
    diffs <- xpathSApply(htmlParse(text), "//a", xmlValue)[-1]
    diffs <- gsub("RRT_|.txt", "", diffs)
    diffs <- diffs[!diffs %in% c('bin/','src/')]
    return( diffs )
  } else {
    cat(text)
  }
}

#' Get available package level metadata from MRAN.
#'
#' @import httr RJSONIO
#' @export
#' @param package Required. A package name
#' @param snapshot An MRAN snapshot ('YYYY-MM-DD_TTTT') or a date ('YYYY-MM-DD'). Defaults to most recent snapshot.
#' @family mran
#' @examples \dontrun{
#' mranPkgMetadata(package="plyr", snapshot="2014-08-04")
#' }
mranPkgMetadata <- function(package, snapshot=NULL){
  snapshot <- snapshotFromDate(snapshot)
  url <- sprintf("%s/%s/%s.json", paste0(mranServerUrl(), '/metadata/logs'), snapshot, package)
  res <- GET(url)
  if(res$status_code > 202){
    msg <- "%s - Package not found, you don't have an internet connection, or other error."
    stop(sprintf(msg, res$status_code))
  }
  text <- content(res, as = "text")
  RJSONIO::fromJSON(text, simplifyWithNames = FALSE)
}





#' Get available package versions from MRAN
#' 
#' @inheritParams checkpoint
#' @inheritParams rrt_install
#'
#' @export
#' @param pkgs (character) Required. A package name
#' @param type (character) "src", "mac.binary" or "win.binary"
#' @param Rversion not yet used

#' @family mran
#' @examples 
#' pkgVersionAtSnapshot(snapshotdate="2014-07-14", pkgs="plyr")
#' pkgVersionAtSnapshot(snapshotdate="2014-08-01", pkgs="plyr", type="win.binary")

pkgVersionAtSnapshot <- function(pkgs, snapshotdate, snapshotid=snapshotFromDate(snapshotdate), 
                            type=c("src", "mac.binary", "win.binary"), Rversion="R3.0") {
  type <- match.arg(type)
  
  doOne <- function(package){
    metadata <- mranPkgMetadata(package, snapshotid)
    getBinary <- function(x) gsub(".*_(.*)\\.(zip|tgz)", "\\1", basename(x))
    switch(type, 
           src = names(metadata$source$ver),
           mac.binary = getBinary(metadata$osx[[1]]),
           win.binary = getBinary(metadata$windows[[1]])
    )
  }
  
  doOneWithErrorChecking <- function(package){
    versions <- tryCatch(doOne(package=package), error=function(e) e)
    if(inherits(versions, "error")){
      sprintf("%s/__notfound__", package)
    } else {
      latestVersion <- function(a, b) if(utils::compareVersion(a, b) <= 0) b else a
      versionInUse <- Reduce(latestVersion, versions)
      
      sprintf("%s/%s_%s.tar.gz", package, package, versionInUse)
    }
    
  }
  
  sapply(pkgs, doOneWithErrorChecking)
  
}





snapshotFromDate <- function(date){
  if(is.null(date)){
    gg <- mranSnapshots(verbose=FALSE)
    gg[length(gg)]
  } else {
    mranSnapshots(date, verbose=FALSE)
  }
}


#' Download R packages from the MRAN server
#'
#' This function uses rsync on *unix machines, which is faster than the method (wget) \code{install.packages} uses by default. On Windows we use your default method of downloading files. This function does not install packages, but only downloads them to your machine.
#'
#' @export
#' 
#' @inheritParams checkpoint
#' @inheritParams rrt_install
#' 
#' @param pkgs Packages to install with version numbers, e.g. plyr_1.8.1
#' @param downloadType Either 'rsync' or 'default'

downloadPackageFromMran <- function(repo, snapshotdate, snapshotid=getSnapshotId(snapshotdate),
                                    pkgs=NULL,  
                                    srcPath=rrtPath(repo, "src"),  
                                    verbose=FALSE, quiet=FALSE, 
                                    downloadType=c("rsync", "default"))
{
  downloadType <- match.arg(downloadType)
  if(is.null(srcPath)) stop("You must specify a directory to download packages to")
  if(is.null(pkgs)) stop("You must specify one or more packages to get")
  
  # get available snapshots
  if(is.null(snapshotid)) snapshotid <- getSnapshotId(snapshotdate, forceLast=TRUE)
  
  
  pkgs <- lapply(pkgs, function(x) strsplit(x, "_")[[1]])
  pkgpaths <- sapply(pkgs, pkgVersionAtSnapshot, snapshotid=snapshotid)
  
  notonmran <- grep("__notfound__", pkgpaths, value = TRUE)
  pkgpaths <- setdiff(pkgpaths, "__notfound__")
  
  mssg(verbose, "... Downloading package files")
  
  #if(!.Platform$OS.type == "unix"){
  switch(downloadType,
         rsync   = downloadPackageSourceUsingRsync(
           pkgpaths, 
           srcPath=srcPath, 
           snapshotid=snapshotid, 
           quiet=quiet
         ),
         default = downloadPackageSourceUsingDefault(
           pkgpaths, 
           srcPath=srcPath, 
           snapshotid=snapshotid, 
           quiet=quiet
         )
  )
}

downloadPackageSourceUsingRsync <- function(pkgpaths, srcPath, snapshotid, quiet=FALSE){
  if(length(pkgpaths > 0)){
    oldwd <- getwd()
    on.exit(setwd(oldwd))
    setwd(srcPath)
    tmpPkgsFileLoc <- "_rsync-file-locations.txt"
    cat(pkgpaths, file = tmpPkgsFileLoc, sep = "\n")
  
    
    url <- mranServerUrl()
    url <- sub("http://", "", url)
    rsyncCmd <- sprintf('rsync -rt --progress --files-from=%s %s::MRAN-src-snapshots/%s .', 
                        tmpPkgsFileLoc, url, snapshotid)
    system(rsyncCmd, intern=TRUE)
    
    mvCmd <- sprintf("mv %s ./", paste(pkgpaths, collapse = " "))
    system(mvCmd)
    
    rmCmd <- sprintf("rm -rf %s", paste(
      sapply(pkgpaths, 
             function(x) strsplit(x, "/")[[1]][[1]], USE.NAMES = FALSE), collapse = " ")
    )
    system(rmCmd)
    system(sprintf("rm %s", tmpPkgsFileLoc))
  }
  
}

downloadPackageSourceUsingDefault <- function(pkgpaths, srcPath, snapshotid, quiet=FALSE){
  downloadOne <- function(x, srcPath, snapshotid, quiet=FALSE){
    pkg <- strsplit(x, "/")[[1]]
    url <- sprintf("%s/snapshots/src/%s/%s", mranServerUrl(), snapshotid, x)
    destfile <- file.path(srcPath, pkg[[2]])
    download.file(url, destfile=destfile, quiet=quiet)
  }
  for(i in seq_along(pkgpaths)){
    downloadOne(pkgpaths[[i]], srcPath=srcPath, snapshotid=snapshotid, quiet=quiet)
  }
  
}

# modifyColClasses <- function (d, colClasses){
#   colClasses <- rep(colClasses, length.out = length(d))
#   d[] <- lapply(seq_along(d), 
#                 function(i) {
#                   switch(colClasses[i],
#                          numeric = as.numeric(d[[i]]), 
#                          character = as.character(d[[i]]),
#                          Date = as.Date(d[[i]], origin = "1970-01-01"), 
#                          POSIXct = as.POSIXct(d[[i]], origin = "1970-01-01"), 
#                          factor = as.factor(d[[i]]), as(d[[i]], colClasses[i]))
#                 })
#   d
# }

# sortDataFrame <- function (data, vars = names(data)){
#   if (length(vars) == 0 || is.null(vars)) {
#     data
#   } else {
#     data[do.call("order", data[, vars, drop = FALSE]), , drop = FALSE]
#   }
# }

getSnapshotId <- function(snapshotdate=Sys.Date(), forceLast=TRUE){
  # get available snapshots
  availsnaps <- mranSnapshots(verbose=FALSE)
  
  snapshots <- grep(snapshotdate, availsnaps, value = TRUE)
  if(length(snapshots) > 1){
    if(!forceLast){
      print(data.frame(snapshots))
      message("\nMore than one snapshot matching your date found \n",
              "Enter rownumber of snapshot (other inputs will return 'NA'):\n")
      take <- scan(n = 1, quiet = TRUE, what = 'raw')
      if(is.na(take)){ message("No snapshot found or you didn't select one") }
      snapshots[as.numeric(take)]
    } else { snapshots[length(snapshots)] }
  } else { snapshots }
}

