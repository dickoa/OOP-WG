% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/property.R
\name{new_property}
\alias{new_property}
\title{Define a new property}
\usage{
new_property(
  class = class_any,
  getter = NULL,
  setter = NULL,
  default = NULL,
  name = NULL
)
}
\arguments{
\item{class}{Class that the property must be an instance of.
See \code{\link[=as_class]{as_class()}} for details.}

\item{getter}{An optional function used to get the value. The function
should take \code{self}  as its sole argument and return the value. If the
property has a \code{class} the class of the value is validated.

If a property has a getter but doesn't have a setter, it is read only.}

\item{setter}{An optional function used to set the value. The function
should take \code{self} and \code{value} and return a modified object.}

\item{default}{When an object is created and the property is not supplied,
what should it default to? If \code{NULL}, defaults to the "empty" instance
of \code{class}.}

\item{name}{Property name, primarily used for error messages. Used
primrarily for testing as it is set automatically when using a list of
properties.}
}
\description{
A property defines a named component of an object. Properties are
typically used to store (meta) data about an object, and are often
limited to a data of a specific \code{class}.

By specifying a \code{getter} and/or \code{setter}, you can make the property
"dynamic" so that it's computed when accessed or has some non-standard
behaviour when modified.
}
\examples{
# Simple properties store data inside an object
pizza <- new_class("pizza", properties = list(
  slices = new_property(class_numeric, default = 10)
))
my_pizza <- pizza(slices = 6)
my_pizza@slices
my_pizza@slices <- 5
my_pizza@slices

your_pizza <- pizza()
your_pizza@slices

# Dynamic properties can compute on demand
clock <- new_class("clock", properties = list(
  now = new_property(getter = function(self) Sys.time())
))
my_clock <- clock()
my_clock@now; Sys.sleep(1)
my_clock@now
# This property is read only
try(my_clock@now <- 10)

# These can be useful if you want to deprecate a property
person <- new_class("person", properties = list(
  first_name = class_character,
  firstName = new_property(
     getter = function(self) {
       warning("@firstName is deprecated; please use @first_name instead", call. = FALSE)
       self@first_name
     },
     setter = function(self, value) {
       warning("@firstName is deprecated; please use @first_name instead", call. = FALSE)
       self@first_name <- value
       self
     }
   )
))
hadley <- person(first_name = "Hadley")
hadley@firstName
hadley@firstName <- "John"
hadley@first_name
}
