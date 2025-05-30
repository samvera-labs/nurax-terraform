# Terraform Infrastructure for Nurax

## Overview

This project contains the [Terraform](https://terraform.io/) scripts required to build and maintain the AWS infrastructure running the Nurax demo/test instances for the [Hyrax](https://github.com/samvera/hyrax) project using the [hyrax-dev container image](https://github.com/samvera/hyrax/pkgs/container/hyrax-dev). 

The resources created include:

- A dedicated [Virtual Private Cloud](https://aws.amazon.com/vpc/), split into six subnets across three availability zones
- An [RDS Postgresql](https://aws.amazon.com/rds/) database instance, with individual databases for the dev, stable, and pg Nurax instances as well as the shared Fedora instance
- An [ElastiCache Redis](https://aws.amazon.com/elasticache/) cluster, for Rails caching and ActiveJob message queueing
- An [Elastic Container Service](https://aws.amazon.com/ecs/) cluster, which hosts the serverless containers running the shared Fedora and Solr instances as well as the individual Nurax containers
- A [Route53](https://aws.amazon.com/route53/) zone, which provides DNS services for the Nurax applications and their dependencies
- The various [IAM](https://aws.amazon.com/iam/) roles, security groups, load balancers, task/service definitions, and SSL certificates required to allow Nurax to run on the above resources

## Use

### Prerequisites

- A working copy of this repository
- The [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/)
- An [AWS Profile](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) with administrative access to the account you will be deploying under (the remainder of this document will assume that profile is called `nurax`)
- [OpenTofu](https://opentofu.org) (Terraform replacement)

### Preparation

1. Set up your AWS environment:
   ```
   export AWS_PROFILE=nurax AWS_REGION=us-east-2
   ```
2. Create a file called `terraform.tfvars` in the project's root directory. The only required variable is the `hosted_zone_name`, but see [`variables.tf`](./variables.tf) for a list of other variables that can be overridden. For the basic (existing) installation, the file should look like this:
   ```
   hosted_zone_name = samvera.org
   ```
3. Install Terraform providers and modules:
   ```
   tofu init
   ```
   The first time you run this, you will be asked for the name of an S3 bucket where the terraform state will be persisted. The existing infrastructure uses a bucket named `nurax-terraform`, which is what you should use unless you are setting up a completely separate instance.
4. Have Terraform check the existing infrastructure against the spec:
   ```
   tofu plan -out terraform.plan
   ```
5. Read over the output to see what changes (if any) Terraform thinks it needs to make to bring things up to spec. If they look correct, have Terraform apply the plan it just saved:
   ```
   tofu apply terraform.plan
   ```

### Console Access
1. Connect to the nurax-console EC2 instance via SSH.
2. Find the task id in the AWS ECS dashboard for the desired nurax instance.
3. Choose webapp or worker container
4. Run `aws ecs execute-command --cluster nurax --task {task id} --container {webapp|worker} --interactive --command "/bin/bash"`
