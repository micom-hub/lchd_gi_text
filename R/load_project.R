# Loader for experimentation at this point. This will go away once it's in a package

packages_script <- file.path(getwd(), "R/setup_dependencies.R")
this_script <- file.path(getwd(), "R/load_project.R")
source(packages_script)

scripts <- list.files(file.path(getwd(), "R"), full.names = T)
r_scripts <- scripts[str_detect(scripts, ".R$")]
# don't re-source packages script and don't loop over this one
filtered <- setdiff(r_scripts, c(packages_script, this_script))
walk(filtered, source)
print("All repo scripts under ./R/ have been sourced")
