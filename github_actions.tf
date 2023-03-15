module "oidc-with-github-actions" {
  source  = "thetestlabs/oidc-with-github-actions/aws"
  version = "0.1.4"

  github_org            = "samvera-labs"
  github_repositories   = ["nurax"]
  iam_role_policy       = "AdministratorAccess"
}
