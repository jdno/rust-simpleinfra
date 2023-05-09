terraform {
  source = "../../../modules//datadog-fastly"
}

include {
  path           = find_in_parent_folders()
  merge_strategy = "deep"
}

inputs = {
  services = [
    "5qaYFyyiorVua6uCZg7It0",
    "gEfRWQihVaQqh6vsPlY0H1",
    "MWlq3AIDXubpbw725c7og3",
    "liljrvY3Xt0CzNk0mpuLa7",
  ]
}
