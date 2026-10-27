here::i_am("R/load_project.R")
# Loader for experimentation at this point. This will go away once it's in a package

packages_script <- here::here("R/setup_dependencies.R")
this_script <- here::here("R/load_project.R")

source(packages_script)

scripts <- list.files(here::here("R"), full.names = T, recursive = T)
r_scripts <- scripts[str_detect(scripts, ".R$")]
# don't re-source packages script and don't loop over this one
filtered <- setdiff(r_scripts, c(packages_script, this_script))
walk(filtered, source)
print("All repo scripts under ./R/ have been sourced")
