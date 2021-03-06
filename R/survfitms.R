# Automatically generated from the noweb directory
# Methods for survfitms objects
dim.survfitms <- function(x) {
    if (is.null(x$strata)) {
        if (is.matrix(x$pstate)) c(1L, ncol(x$pstate))
        else 1L
    }
    else {
        nr <- length(x$strata)
        if (is.matrix(x$pstate)) c(nr, ncol(x$pstate))
        else nr
    }
}
summary.survfit <- function(object, times, censored=FALSE, 
                            scale=1, extend=FALSE, 
                            rmean=getOption('survfit.rmean'),
                            ...) {
    fit <- object  #make a local copy
    if (!inherits(fit, 'survfit'))
            stop("summary.survfit can only be used for survfit objects")

    # The print.rmean option is depreciated, it is still listened
    #   to in print.survfit, but ignored here
    if (is.null(rmean)) rmean <- "common"
    if (is.numeric(rmean)) {
        if (is.null(object$start.time)) {
            if (rmean < min(object$time)) 
                stop("Truncation point for the mean is < smallest survival")
        }
        else if (rmean < object$start.time)
            stop("Truncation point for the mean is < smallest survival")
    }
    else {
        rmean <- match.arg(rmean, c('none', 'common', 'individual'))
        if (length(rmean)==0) stop("Invalid value for rmean option")
    }

    temp <- survmean(fit, scale=scale, rmean)  
    table <- temp$matrix  #for inclusion in the output list
    rmean.endtime <- temp$end.time
    
    fit$time <- fit$time/scale
    if (!is.null(fit$strata)) {
        nstrat <-  length(fit$strata)
    }    
    delta <- function(x, indx) {  # sums between chosen times
        if (is.logical(indx)) indx <- which(indx)
        if (!is.null(x) && length(indx) >0) {
            fx <- function(x, indx) diff(c(0, c(0, cumsum(x))[indx+1]))
            if (is.matrix(x)) {
                temp <- apply(x, 2, fx, indx=indx)
                # don't return a vector when only 1 time point is given
                if (is.matrix(temp)) temp else matrix(temp, nrow=1)
            }
            else fx(x, indx)
        }
        else NULL
    }

    if (missing(times)) {
        if (!censored) {
            index <- (rowSums(as.matrix(fit$n.event)) >0)
            for (i in c("time","n.risk", "n.event", "surv", "pstate", "std.err", 
                                "upper", "lower", "cumhaz")) {
                if (!is.null(fit[[i]])) {  # not all components in all objects
                    temp <- fit[[i]]
                    if (!is.array(temp)) temp <- temp[index]  #simple vector
                    else if (is.matrix(temp)) temp <- temp[index,,drop=FALSE]
                    else temp <- temp[,,index, drop=FALSE] # 3 way
                    fit[[i]] <- temp
                }
            }
            # The n.enter and n.censor values are accumualated
            #  both of these are simple vectors
            if (is.null(fit$strata)) {
                for (i in c("n.enter", "n.censor"))
                    if (!is.null(fit[[i]]))
                        fit[[i]] <- delta(fit[[i]], index)
            }
            else {
                sindx <- rep(1:nstrat, fit$strata)
                for (i in c("n.enter", "n.censor")) {
                    if (!is.null(fit[[i]]))
                        fit[[i]] <- unlist(sapply(1:nstrat, function(j) 
                                     delta(fit[[i]][sindx==j], index[sindx==j])))
                }
                # the "factor" is needed for the case that a strata has no
                #  events at all, and hence 0 lines of output
                fit$strata[] <- as.vector(table(factor(sindx[index], 1:nstrat))) 
            }
        }
        #if missing(times) and censored=TRUE, the fit object is ok as it is
    }
    else {
        ssub <- function(x, indx, init=0) {  #select an object and index
            if (!is.null(x) && length(indx)>0) {
                # the as.vector() is a way to keep R from adding "init" as a row name
                if (is.matrix(x)) rbind(as.vector(init), x)[indx+1,,drop=FALSE]
                else c(init, x)[indx+1]
            }
            else NULL
        }

        # The left.open argument was added to findInterval in R 3.3, but
        #  our local servers are version 3.2.x.  Work around it.
        find2 <- function(x, vec, left.open=FALSE, ...) {
            if (!left.open) findInterval(x, vec, ...)
            else length(vec) - findInterval(-x, rev(-vec), ...)
        }
        findrow <- function(fit, times, extend, init=1) {
            # First, toss any printing times that are outside our range
            if (is.null(fit$start.time)) mintime <- min(fit$time, 0)
            else                         mintime <- fit$start.time
            ptimes <- times[times >= mintime]

            if (!extend) {
                maxtime <- max(fit$time)
                ptimes <- ptimes[ptimes <= maxtime]
            }
            ntime <- length(fit$time)
            
            index1 <- find2(ptimes, fit$time) 
            index2 <- 1 + find2(ptimes, fit$time, left.open=TRUE)
            # The pmax() above encodes the assumption that n.risk for any
            #  times before the first observation = n.risk at the first obs
            fit$time <- ptimes
            for (i in c("surv", "pstate", "upper", "lower")) {
                if (!is.null(fit[[i]])) fit[[i]] <- ssub(fit[[i]], index1, init)
            }
            for (i in c("std.err", "cumhaz")) {
                if (!is.null(fit[[i]])) fit[[i]] <- ssub(fit[[i]], index1, 0)
            }
            
            if (is.matrix(fit$n.risk)) {
                # Every observation in the data has to end with a censor or event.
                #  So by definition the number at risk after the last observed time
                #  value must be 0.
                fit$n.risk <- rbind(fit$n.risk,0)[index2,,drop=FALSE]
            }
            else  fit$n.risk <- c(fit$n.risk, 0)[index2]

            for (i in c("n.event", "n.censor", "n.enter"))
                fit[[i]] <- delta(fit[[i]], index1)
            fit
        }

        # For a single component, turn it from a list into a single vector, matrix
        #  or array
        unlistsurv <- function(x, name) {
            temp <- lapply(x, function(x) x[[name]])
            if (is.vector(temp[[1]])) unlist(temp)
            else if (is.matrix(temp[[1]])) do.call("rbind", temp)
            else { 
                # the cumulative hazard is the only component that is an array
                # it's third dimension is n
                xx <- unlist(temp)
                dd <- dim(temp[[1]])
                dd[3] <- length(xx)/prod(dd[1:2])
                array(xx, dim=dd)
            }
        }

        # unlist all the components built by a set of calls to findrow
        #  and remake the strata
        unpacksurv <- function(fit, ltemp) {
            keep <- c("time", "surv", "pstate", "upper", "lower", "std.err",
                      "cumhaz", "n.risk", "n.event", "n.censor", "n.enter")
            for (i in keep) 
                if (!is.null(fit[[i]])) fit[[i]] <- unlistsurv(ltemp, i)
            fit$strata[] <- sapply(ltemp, function(x) length(x$time))
            fit
        }
        times <- sort(times)  #in case the user forgot
        if (is.null(fit$strata)) fit <- findrow(fit, times, extend)
        else {
            ltemp <- vector("list", nstrat)
            for (i in 1:nstrat) 
                ltemp[[i]] <- findrow(fit[i], times, extend)
            fit <- unpacksurv(fit, ltemp)
        }
    }

    # finish off the output structure
    fit$table <- table
    if (length(rmean.endtime)>0  && !any(is.na(rmean.endtime[1]))) 
            fit$rmean.endtime <- rmean.endtime

    # An ordinary survfit object contains std(cum hazard), change scales
    if (!is.null(fit$std.err)) fit$std.err <- fit$std.err * fit$surv 
 
    # Expand the strata
    if (!is.null(fit$strata)) 
        fit$strata <- factor(rep(1:nstrat, fit$strata), 1:nstrat,
                             labels= names(fit$strata))
    class(fit) <- "summary.survfit"
    fit
}
summary.survfitms <- function(object, times, censored=FALSE, 
                            scale=1, extend=FALSE, 
                            rmean= getOption("survfit.rmean"),
                            ...) {
    fit <- object
    if (!inherits(fit, 'survfitms'))
            stop("summary.survfitms can only be used for survfitms objects")

    # The print.rmean option is depreciated, it is still listened
    #   to in print.survfit, but ignored here
    if (is.null(rmean)) rmean <- "common"
    if (is.numeric(rmean)) {
        if (is.null(object$start.time)) {
            if (rmean < min(object$time)) 
                stop("Truncation point for the mean is < smallest survival")
        }
        else if (rmean < object$start.time)
            stop("Truncation point for the mean is < smallest survival")
    }
    else {
        rmean <- match.arg(rmean, c('none', 'common', 'individual'))
        if (length(rmean)==0) stop("Invalid value for rmean option")
    }

    temp <- survmean2(fit, scale=scale, rmean)  
    table <- temp$matrix  #for inclusion in the output list
    rmean.endtime <- temp$end.time

    if (!missing(times)) {
        if (!is.numeric(times)) stop ("times must be numeric")
        times <- sort(times)
    }
    fit$time <- fit$time/scale
    if (!is.null(fit$strata)) {
        nstrat <-  length(fit$strata)
        sindx <- rep(1:nstrat, fit$strata)
    }    
    delta <- function(x, indx) {  # sums between chosen times
        if (is.logical(indx)) indx <- which(indx)
        if (!is.null(x) && length(indx) >0) {
            fx <- function(x, indx) diff(c(0, c(0, cumsum(x))[indx+1]))
            if (is.matrix(x)) {
                temp <- apply(x, 2, fx, indx=indx)
                if (is.matrix(temp)) temp else matrix(temp, nrow=1)
            }
            else fx(x, indx)
        }
        else NULL
    }

    if (missing(times)) {
        if (!censored) {
            index <- (rowSums(as.matrix(fit$n.event)) >0)
            for (i in c("time","n.risk", "n.event", "surv", "pstate", "std.err", 
                                "upper", "lower", "cumhaz")) {
                if (!is.null(fit[[i]])) {  # not all components in all objects
                    temp <- fit[[i]]
                    if (!is.array(temp)) temp <- temp[index]  #simple vector
                    else if (is.matrix(temp)) temp <- temp[index,,drop=FALSE]
                    else temp <- temp[,,index, drop=FALSE] # 3 way
                    fit[[i]] <- temp
                }
            }
            # The n.enter and n.censor values are accumualated
            #  both of these are simple vectors
            if (is.null(fit$strata)) {
                for (i in c("n.enter", "n.censor"))
                    if (!is.null(fit[[i]]))
                        fit[[i]] <- delta(fit[[i]], index)
            }
            else {
                sindx <- rep(1:nstrat, fit$strata)
                for (i in c("n.enter", "n.censor")) {
                    if (!is.null(fit[[i]]))
                        fit[[i]] <- unlist(sapply(1:nstrat, function(j) 
                                     delta(fit[[i]][sindx==j], index[sindx==j])))
                }
                # the "factor" is needed for the case that a strata has no
                #  events at all, and hence 0 lines of output
                fit$strata[] <- as.vector(table(factor(sindx[index], 1:nstrat))) 
            }
        }
        #if missing(times) and censored=TRUE, the fit object is ok as it is
    }
    else {
        ssub <- function(x, indx, init=0) {  #select an object and index
            if (!is.null(x) && length(indx)>0) {
                # the as.vector() is a way to keep R from adding "init" as a row name
                if (is.matrix(x)) rbind(as.vector(init), x)[indx+1,,drop=FALSE]
                else c(init, x)[indx+1]
            }
            else NULL
        }

        # The left.open argument was added to findInterval in R 3.3, but
        #  our local servers are version 3.2.x.  Work around it.
        find2 <- function(x, vec, left.open=FALSE, ...) {
            if (!left.open) findInterval(x, vec, ...)
            else length(vec) - findInterval(-x, rev(-vec), ...)
        }
        findrow <- function(fit, times, extend, init=1) {
            # First, toss any printing times that are outside our range
            if (is.null(fit$start.time)) mintime <- min(fit$time, 0)
            else                         mintime <- fit$start.time
            ptimes <- times[times >= mintime]

            if (!extend) {
                maxtime <- max(fit$time)
                ptimes <- ptimes[ptimes <= maxtime]
            }
            ntime <- length(fit$time)
            
            index1 <- find2(ptimes, fit$time) 
            index2 <- 1 + find2(ptimes, fit$time, left.open=TRUE)
            # The pmax() above encodes the assumption that n.risk for any
            #  times before the first observation = n.risk at the first obs
            fit$time <- ptimes
            for (i in c("surv", "pstate", "upper", "lower")) {
                if (!is.null(fit[[i]])) fit[[i]] <- ssub(fit[[i]], index1, init)
            }
            for (i in c("std.err", "cumhaz")) {
                if (!is.null(fit[[i]])) fit[[i]] <- ssub(fit[[i]], index1, 0)
            }
            
            if (is.matrix(fit$n.risk)) {
                # Every observation in the data has to end with a censor or event.
                #  So by definition the number at risk after the last observed time
                #  value must be 0.
                fit$n.risk <- rbind(fit$n.risk,0)[index2,,drop=FALSE]
            }
            else  fit$n.risk <- c(fit$n.risk, 0)[index2]

            for (i in c("n.event", "n.censor", "n.enter"))
                fit[[i]] <- delta(fit[[i]], index1)
            fit
        }

        # For a single component, turn it from a list into a single vector, matrix
        #  or array
        unlistsurv <- function(x, name) {
            temp <- lapply(x, function(x) x[[name]])
            if (is.vector(temp[[1]])) unlist(temp)
            else if (is.matrix(temp[[1]])) do.call("rbind", temp)
            else { 
                # the cumulative hazard is the only component that is an array
                # it's third dimension is n
                xx <- unlist(temp)
                dd <- dim(temp[[1]])
                dd[3] <- length(xx)/prod(dd[1:2])
                array(xx, dim=dd)
            }
        }

        # unlist all the components built by a set of calls to findrow
        #  and remake the strata
        unpacksurv <- function(fit, ltemp) {
            keep <- c("time", "surv", "pstate", "upper", "lower", "std.err",
                      "cumhaz", "n.risk", "n.event", "n.censor", "n.enter")
            for (i in keep) 
                if (!is.null(fit[[i]])) fit[[i]] <- unlistsurv(ltemp, i)
            fit$strata[] <- sapply(ltemp, function(x) length(x$time))
            fit
        }
        times <- sort(times)
        if (is.null(fit$strata)) fit <- findrow(fit, times, extend, fit$p0)
        else {
            ltemp <- vector("list", nstrat)
            for (i in 1:nstrat) 
                ltemp[[i]] <- findrow(fit[i], times, extend, fit$p0[i,])
            fit <- unpacksurv(fit, ltemp)
        }
    }

    # finish off the output structure
    fit$table <- table
    if (length(rmean.endtime)>0  && !any(is.na(rmean.endtime))) 
            fit$rmean.endtime <- rmean.endtime

     if (!is.null(fit$strata)) 
        fit$strata <- factor(rep(names(fit$strata), fit$strata))
    class(fit) <- "summary.survfitms"
    fit
}

print.survfitms <- function(x, scale=1,
                            rmean = getOption("survfit.rmean"), ...) {
    if (!is.null(cl<- x$call)) {
        cat("Call: ")
        dput(cl)
        cat("\n")
        }        
    omit <- x$na.action
    if (length(omit)) cat("  ", naprint(omit), "\n")

    if (is.null(rmean)) rmean <- "common"
    if (is.numeric(rmean)) {
        if (is.null(x$start.time)) {
            if (rmean < min(x$time)) 
                stop("Truncation point for the mean is < smallest survival")
        }
        else if (rmean < x$start.time)
            stop("Truncation point for the mean is < smallest survival")
    }
    else {
        rmean <- match.arg(rmean, c('none', 'common', 'individual'))
        if (length(rmean)==0) stop("Invalid value for rmean option")
    }

    temp <- survmean2(x, scale=scale, rmean)
    if (is.null(temp$end.time)) print(temp$matrix, ...)
    else {
        etime <- temp$end.time
        dd <- dimnames(temp$matrix)
        cname <- dd[[2]]
        cname[length(cname)] <- paste0(cname[length(cname)], '*')
        dd[[2]] <- cname
        dimnames(temp$matrix) <- dd
        print(temp$matrix, ...)
        if (length(etime) ==1)
             cat("   *mean time in state, restricted (max time =", 
                 format(etime, ...), ")\n")
        else cat("   *mean time in state, restricted (per curve cutoff)\n")
    }
    invisible(x)
}
survmean2 <- function(x, scale, rmean) {
    nstate <- length(x$states)  #there will always be at least 1 state
    ngrp   <- max(1, length(x$strata))
    if (ngrp >1)  {
        igrp <- rep(1:ngrp, x$strata)
        rname <- names(x$strata)
        }
    else {
        igrp <- rep(1, length(x$time))
        rname <- NULL
        }

    # The n.event matrix may not have nstate columms.  Its
    #  colnames are the first elements of states, however
    if (is.matrix(x$n.event)) {
        nc <- ncol(x$n.event)
        nevent <- tapply(x$n.event, list(rep(igrp, nc), col(x$n.event)), sum)
        dimnames(nevent) <- list(rname, x$states[1:nc])
        }
    else {
        nevent <- tapply(x$n.event, igrp, sum)
        names(nevent) <- rname
        }

    outmat <- matrix(0., nrow=nstate*ngrp , ncol=2)
    outmat[,1] <- rep(x$n, nstate)
    outmat[1:length(nevent), 2] <- c(nevent)
  
    if (ngrp >1) 
        rowname <- c(outer(rname, x$states, paste, sep=", "))
    else rowname <- x$states

    # Caculate the mean time in each state
    if (rmean != "none") {
        if (is.numeric(rmean)) maxtime <- rep(rmean, ngrp)
        else if (rmean=="common") maxtime <- rep(max(x$time), ngrp)
        else maxtime <- tapply(x$time, igrp, max)
    
        meantime <- matrix(0., ngrp, nstate)
        p0 <- matrix(x$p0, nrow=ngrp)  #in case there is only one row
        if (!is.null(x$influence)) stdtime <- meantime
        for (i in 1:ngrp) {
            if (is.matrix(x$pstate))
                temp <- rbind(p0[i,], x$pstate[igrp==i,, drop=FALSE])
            else temp <- matrix(c(p0[i], x$pstate[igrp==i]), ncol=1)

            if (is.null(x$start.time)) tt <- c(0, x$time[igrp==i])
            else tt <- c(x$start.time, x$time[igrp==i])

            # Now cut it off at maxtime
            delta <- diff(c(tt[tt<maxtime[i]], maxtime[i]))
            if (length(delta) > nrow(temp)) delta <- delta[1:nrow(temp)]
            if (length(delta) < nrow(temp))
                delta <- c(delta, rep(0, nrow(temp) - length(delta)))
            meantime[i,] <- colSums(delta*temp)

            if (!is.null(x$influence)) {
                # calculate the variance
                if (is.list(x$influence))
                    itemp <- apply(x$influence[[i]], 1,
                                   function(x) colSums(x*delta))
                else itemp <- apply(x$influence, 1,
                                    function(x) colSums(x*delta))
                stdtime[i,] <- sqrt(rowSums(itemp^2))
           }
        }
        outmat <- cbind(outmat, c(meantime)/scale)
        cname <- c("n", "nevent", "rmean")
        if (!is.null(x$influence)) {
            outmat <- cbind(outmat, c(stdtime)/scale)
            cname <- c(cname, "std(rmean)")
        }
        # report back a single time, if there is only one
        if (all(maxtime == maxtime[1])) maxtime <- maxtime[1]
    }
    else cname <- c("n", "nevent")
    dimnames(outmat) <- list(rowname, cname)

    if (rmean=='none') list(matrix=outmat)
    else list(matrix=outmat, end.time=maxtime/scale)
}
"[.survfitms" <- function(x, ..., drop=TRUE) {
    nmatch <- function(indx, target) { 
        # This function lets R worry about character, negative, or logical subscripts
        #  It always returns a set of positive integer indices
        temp <- 1:length(target)
        names(temp) <- target
        temp[indx]
    }
        
    if (missing(..1)) i<- NULL  else i <- ..1  # rows
    if (missing(..2)) j<- NULL  else j <- ..2  # cols
    n <- length(x$time)

    if (is.null(x$strata) && is.matrix(x$pstate)) {
        # No strata, but a matrix of P(state) values
        #  In this case, allow them to use a single i subscript as well
        if (is.null(j) && !is.null(i)) {
            j <- i
            i <- NULL
        }
    }

    # 'i' is the subscript from the user's point of view, 'i2' is the
    #  subscript from the program's view, i.e, the row indices to keep
    if (is.null(i)) {
        i2 <- 1:n
        if (is.null(x$strata)) i <- 1
        else i <- seq(along=x$strata)
    }
    else {
        if (is.null(x$strata) && (length(i) > 1 || i != 1))
            stop("subscript out of bounds")
        indx <- nmatch(i, names(x$strata)) #strata to keep
        if (any(is.na(indx))) 
            stop(paste("strata", 
                       paste(i[is.na(indx)], collapse=' '),
                       'not matched'))
        # Now, i may not be in order: a user has curve[3:2] to reorder 
        #  a plot.  Hence the "unlist(lapply(" construct which will reorder
        #  the data in the curves
        temp <- rep(1:length(x$strata), x$strata)
        i2 <- unlist(lapply(i, function(x) which(temp==x)))

        if (length(i) <=1 && drop) x$strata <- NULL
        else               x$strata  <- x$strata[indx]
     }

    if (!is.null(j)) {
        indx <- nmatch(j, x$states)
        if (any(is.na(indx)))
            stop("subscript out of bounds", j[is.na(indx)])
        else j <- as.vector(indx)
    }

    # if only one state is kept, still retain the data as a matrix
    if (length(i2) ==1 && !is.null(j) && missing(drop)) drop <- FALSE
 
    # all the elements that can have "nstate" elements or columns
    #  The n.event variable can have fewer
    temp <- c("n.risk", "n.event", "n.censor", "pstate", 
              "cumhaz", "std.err", "lower", "upper")
    sfun <- function(z) {
        if (is.null(j)) {
            if (is.array(z)) {
                if (length(dim(z)) > 2) z[,,i2, drop=drop]  
                else z[i2,,drop=drop]
            }
            else z[i2]
        }
        else {
            if (is.array(z)) {
                if (length(dim(z)) > 2) z[j,j,i2, drop=drop]  
                else z[i2,j, drop=drop]
            }
            else z[i2]
        }
    }
    for (k in temp) x[[k]] <- sfun(x[[k]])
    if (!is.null(j)) x$states <- x$states[j]
    x$n <- x$n[i]
    x$time <- x$time[i2]
    x$transitions <- NULL  # this is incorrect after subscripting

    if (is.matrix(x$p0)) {
        if (is.null(j)) x$p0<- x$p0[i,]
        else x$p0 <- x$p0[i,j]  
    }
    else if (!is.null(j)) x$p0 <- x$p0[j]
    if (!is.null(x$influence)) {
        if (length(i) >1) x$influence <- x$influence[i]
        else if (is.list(x$influence)) x$influence <- x$influence[[i]]
    
        if (!is.null(j)) {
            if (is.list(x$influence)) 
                x$influence <- lapply(x$influence, function(x) x[,j,])
            else x$influence <- x$influence[,j,]
        }
    }
    x
}
