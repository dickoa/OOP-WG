#' Register a R7 method for a generic
#'
#' @description
#' A generic defines the interface of a function. Once you have created a
#' generic with [new_generic()], you provide implementations for specific
#' signatures by registering methods with `method<-`
#'
#' The goal is for `method<-` to be the single function you need when working
#' with R7 generics or R7 classes. This means that as well as registering
#' methods for R7 classes on R7 generics, you can also register methods for
#' R7 classes on S3 or S4 generics, and S3 or S4 classes on R7 generics.
#' But this is not a general method registration function: at least one of
#' `generic` and `signature` needs to be from R7.
#'
#' @param generic A generic function, either created by [new_generic()],
#'   [new_external_generic()], or an existing S3 generic.
#' @param signature A method signature. For R7 generics that use single
#'   dispatch, this must be one of the following:
#'   * An R7 class (created by [new_class()]).
#'   * An R7 union (created by [new_union()]).
#'   * An S3 class (created by [new_S3_class()]).
#'   * An S4 class (created by [methods::getClass()] or [methods::new()]).
#'   * A base type like [class_logical], [class_integer], or [class_numeric].
#'   * A special type like [class_missing] or [class_any].
#'
#'   For R7 generics that use multiple dispatch, this must be a list of any of
#'   the above types.
#'
#'   For S3 generics, this must be an R7 class.
#' @param value A function that implements the generic specification for the
#'   given `signature`.
#' @export
#' @examples
#' # Create a generic
#' bizarro <- new_generic("bizarro", "x")
#' # Register some methods
#' method(bizarro, class_numeric) <- function(x) rev(x)
#' method(bizarro, new_S3_class("data.frame")) <- function(x) {
#'   x[] <- lapply(x, bizarro)
#'   rev(x)
#' }
#'
#' # Using a generic calls the methods automatically
#' bizarro(head(mtcars))
`method<-` <- function(generic, signature, value) {
  register_method(generic, signature, value, env = parent.frame())
  invisible(generic)
}

register_method <- function(generic, signature, method, env = parent.frame()) {
  package <- packageName(env)
  generic <- as_generic(generic)
  signature <- as_signature(signature, generic)

  if (is_external_generic(generic)) {
    register_external_method(generic, signature, method, package)
  } else if (is_S3_generic(generic)) {
    register_S3_method(generic, signature, method)
  } else if (inherits(generic, "genericFunction")) {
    register_S4_method(generic, signature, method, env)
  } else {
    check_method(method, generic, name = method_name(generic, signature))
    register_R7_method(generic, signature, method)
  }

  invisible()
}

register_external_method <- function(generic, signature, method, package = NULL) {
  if (!is.null(package)) {
    # method registration within package, so add to lazy registry
    external_methods_add(package, generic, signature, method)
  } else {
    # otherwise find the generic and register
    generic <- getFromNamespace(generic$name, asNamespace(generic$package))
    register_method(generic, signature, method)
  }
}

register_S3_method <- function(generic, signature, method) {
  if (class_type(signature[[1]]) != "R7") {
    msg <- sprintf(
      "When registering methods for S3 generic %s(), signature must be an R7 class, not %s.",
      generic$name,
      class_friendly(signature[[1]])
    )
    stop(msg, call. = FALSE)
  }
  class <- signature[[1]]@name
  registerS3method(generic$name, class, method, envir = parent.frame())
}

register_R7_method <- function(generic, signature, method) {
  # Flatten out unions to individual signatures
  signatures <- flatten_signature(signature)

  # Register each method
  for (signature in signatures) {
    method <- R7_method(method, generic = generic, signature = signature)
    generic_add_method(generic, signature, method)
  }

  invisible()
}

flatten_signature <- function(signature) {
  # Unpack unions
  sig_is_union <- vlapply(signature, is_union)
  signature[sig_is_union] <- lapply(signature[sig_is_union], "[[", "classes")
  signature[!sig_is_union] <- lapply(signature[!sig_is_union], list)

  # Create grid of indices
  indx <- lapply(signature, seq_along)
  comb <- as.matrix(rev(do.call("expand.grid", rev(indx))))
  colnames(comb) <- NULL

  rows <- lapply(1:nrow(comb), function(i) comb[i, ])
  lapply(rows, function(row) Map("[[", signature, row))
}

as_signature <- function(signature, generic) {
  if (inherits(signature, "R7_signature")) {
    return(signature)
  }

  n <- generic_n_dispatch(generic)
  if (n == 1) {
    new_signature(list(as_class(signature, arg = "signature")))
  } else {
    check_signature_list(signature, n)
    for (i in seq_along(signature)) {
      signature[[i]] <- as_class(signature[[i]], arg = sprintf("signature[[%i]]", i))
    }
    new_signature(signature)
  }
}

check_signature_list <- function(x, n, arg = "signature") {
  if (!is.list(x) || is.object(x)) {
    stop(sprintf("`%s` must be a list for multidispatch generics", arg), call. = FALSE)
  }
  if (length(x) != n) {
    stop(sprintf("`%s` must be length %i", arg, n), call. = FALSE)
  }
}

new_signature <- function(x) {
  class(x) <- "R7_signature"
  x
}

check_method <- function(method, generic, name = paste0(generic@name, "(???)")) {
  if (!is.function(method)) {
    stop(sprintf("%s must be a function", name), call. = FALSE)
  }

  generic_formals <- formals(args(generic))
  method_formals <- formals(method)
  generic_args <- names(generic_formals)
  method_args <- names(method_formals)

  if (!"..." %in% generic_args && !identical(generic_formals, method_formals)) {
    msg <- sprintf(
      "%s() lacks `...` so method formals must match generic formals exactly",
      generic@name
    )
    stop(msg, call. = FALSE)
  }

  n_dispatch <- length(generic@dispatch_args)
  has_dispatch <- length(method_formals) >= n_dispatch &&
    identical(method_args[1:n_dispatch], generic@dispatch_args)
  if (!has_dispatch) {
    msg <- sprintf(
      "%s() dispatches on %s, but %s has arguments %s",
      generic@name,
      arg_names(generic@dispatch_args),
      name,
      arg_names(method_args)
    )
    stop(msg, call. = FALSE)
  }

  empty_dispatch <- vlapply(method_formals[generic@dispatch_args], identical, quote(expr = ))
  if (any(!empty_dispatch)) {
    msg <- sprintf(
      "In %s, dispatch arguments (%s) must not have default values",
      name,
      arg_names(generic@dispatch_args)
    )
    stop(msg, call. = FALSE)
  }

  extra_args <- setdiff(names(generic_formals), c(generic@dispatch_args, "..."))
  for (arg in extra_args) {
    if (!arg %in% method_args) {
      warning(sprintf("%s doesn't have argument `%s`", name, arg), call. = FALSE)
    } else if (!identical(generic_formals[[arg]], method_formals[[arg]])) {
      msg <- sprintf(
        paste0(
          "In %s, default value of `%s` is not the same as the generic\n",
          "- Generic: %s\n",
          "- Method:  %s"
        ),
        name,
        arg,
        deparse1(generic_formals[[arg]]),
        deparse1(method_formals[[arg]])
      )
      warning(msg, call. = FALSE)
    }
  }

  invisible(TRUE)
}

register_S4_method <- function(generic, signature, method, env = parent.frame()) {
  S4_env <- topenv(env)
  S4_signature <- lapply(signature, S4_class, S4_env = S4_env)
  methods::setMethod(generic, S4_signature, method, where = S4_env)
}
S4_class <- function(x, S4_env) {
  if (is_base_class(x)) {
    x@name
  } else if (is_S4_class(x)) {
    x
  } else if (is_class(x) || is_S3_class(x)) {
    class <- tryCatch(methods::getClass(class_register(x)), error = function(err) NULL)
    if (is.null(class)) {
      msg <- sprintf(
        "Class has not been registered with S4; please call S4_register(%s)",
        class_deparse(x)
      )
      stop(msg, call. = FALSE)
    }
    class
  } else {
    stop("Unsupported")
  }
}

#' @export
print.R7_method <- function(x, ...) {
  signature <- method_signature(x@generic, x@signature)
  cat("<R7_method> ", signature, "\n", sep = "")

  attributes(x) <- NULL
  print(x)
}

arg_names <- function(x) {
  paste0(encodeString(x, quote = "`"), collapse = ", ")
}

method_name <- function(generic, signature) {
  method_args <- paste0(vcapply(signature, class_desc), collapse =", ")
  sprintf("%s(%s)", generic@name, method_args)
}
