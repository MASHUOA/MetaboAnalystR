% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/stats_chemometrics.R
\name{PlotPCABiplot}
\alias{PlotPCABiplot}
\title{Create PCA Biplot, set xpd = T to plot outside margin}
\usage{
PlotPCABiplot(mSetObj=NA, imgName, format="png", dpi=default.dpi, width=NA, inx1, inx2)
}
\arguments{
\item{mSetObj}{Input name of the created mSet Object}

\item{imgName}{Input a name for the plot}

\item{format}{Select the image format, "png", or "pdf".}

\item{dpi}{Input the dpi. If the image format is "pdf", users need not define the dpi. For "png" images, 
the default dpi is 72. It is suggested that for high-resolution images, select a dpi of 300.}

\item{width}{Input the width, there are 2 default widths, the first, width = NULL, is 10.5.
The second default is width = 0, where the width is 7.2. Otherwise users can input their own width.}

\item{inx1}{Numeric, indicate the number of the principal component for the x-axis of the loading plot.}

\item{inx2}{Numeric, indicate the number of the principal component for the y-axis of the loading plot.}
}
\description{
Rotate PCA analysis
}
\author{
Jeff Xia\email{jeff.xia@mcgill.ca}
McGill University, Canada
License: GNU GPL (>= 2)
}
