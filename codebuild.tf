# codebuild.tf
resource "aws_codebuild_project" "github_actions_runner" {
  name          = "github-actions-runner"
  description   = "GitHub Actions runner on AWS CodeBuild"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 30 # minutes

  # Ensure IAM policy is attached before creating project
  depends_on = [aws_iam_role_policy.codebuild_policy]

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild_logs.name
      status     = "ENABLED"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/prprasad2020/gh-actions-on-codebuild"

    git_submodules_config {
      fetch_submodules = false
    }
  }

  vpc_config {
    vpc_id = "vpc-0eacd6728f66e09bc"
    subnets = [
      "subnet-0c8cc6865d45658f6",
      "subnet-063c5d9fa7bfac3f9"
    ]
    security_group_ids = [
      aws_security_group.codebuild_runners_sg.id
    ]
  }
}

# GitHub webhook configuration
resource "aws_codebuild_webhook" "github_actions" {
  project_name = aws_codebuild_project.github_actions_runner.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
  }
}

resource "aws_codebuild_source_credential" "github" {
  auth_type   = "CODECONNECTIONS"
  server_type = "GITHUB"
  token       = aws_codestarconnections_connection.github.arn
}

resource "aws_codestarconnections_connection" "github" {
  name          = "gha-runner-connection"
  provider_type = "GitHub"

  tags = {
    Name = "gha-runner-connection"
  }
}

resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/github-actions-runner"
  retention_in_days = 1

  tags = {
    Name = "github-actions-runner-logs"
  }
}

resource "aws_security_group" "codebuild_runners_sg" {
  name        = "codebuild-runners-sg"
  description = "Security group for CodeBuild project"
  vpc_id      = "vpc-0eacd6728f66e09bc"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
