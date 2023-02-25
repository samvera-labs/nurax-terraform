resource "aws_ecs_cluster" "solrcloud" {
  name = "solrcloud"
}

resource "aws_cloudwatch_log_group" "solrcloud_logs" {
  name                = "/ecs/solrcloud"
  retention_in_days   = 3
}
