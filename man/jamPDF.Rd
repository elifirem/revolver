% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/jamPDF.R
\name{jamPDF}
\alias{jamPDF}
\title{PDF jamming function}
\usage{
jamPDF(in.files, out.file = "jamPDF.pdf", layout = "3x3",
  delete.original = TRUE, crop.white = TRUE, page = "none",
  hide.output = TRUE, ignore.stderr = TRUE)
}
\arguments{
\item{in.files}{A bunch of input PDF file names}

\item{out.file}{Output file, cannot be NA}

\item{layout}{A layout to assemble PDFs. For isntance "1x1" is one PDF per page, etc.}

\item{delete.original}{TRUE to delete the input files}

\item{crop.white}{TRUE to trim each margin by a factor 3 (white space removal)}

\item{page}{Set it to any like "a4" or "a3" etc to resize each PDF to that format. Leave it to "none"
to avoid this step}

\item{hide.output}{TRUE to avoid showing to screen the output of system() calls}

\item{ignore.stderr}{TRUE to ignore standard error}
}
\value{
None
}
\description{
This function allows to combine PDFs in a simple way. It uses pdfjam to assemble files,
and pdfScale.sh to resize the output. The script is included in inst/bin, but pdfjam no.
}
