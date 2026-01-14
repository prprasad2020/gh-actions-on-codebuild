---
title: "Running GitHub Actions on AWS CodeBuild"
description: "A complete guide to setting up self-hosted GitHub Actions runners on AWS CodeBuild using Terraform"
date: 2025-11-07T20:00:00Z
image: "@assets/blog/github-actions-on-codebuild.png"
author: "Priyankar Prasad"
draft: false
categories: ["Infrastructure"]
tags: ["AWS", "CodeBuild", "GitHubActions", "Terraform", "CI/CD"]
---

## Introduction

When it comes to self-hosted GitHub Actions runners, teams typically choose between Kubernetes-based solutions (Actions Runner Controller) and managed services. While Kubernetes offers flexibility and control, it comes with operational overhead: managing the cluster, scaling controllers, handling pod lifecycle, and maintaining runner images.

AWS CodeBuild offers a compelling alternative by providing self-hosted runners without the Kubernetes complexity. Unlike Kubernetes-based runners that require cluster management and persistent infrastructure, CodeBuild provisions fresh instances on-demand for each job, eliminating the need to maintain long-running pods or manage autoscaling configurations.

**Key advantages over Kubernetes-based runners:**
- **Zero infrastructure management**: No cluster to maintain, no node scaling, no pod orchestration
- **Native AWS integration**: Direct access to AWS services via IAM roles without additional configuration
- **Cost efficiency**: Pay only for build time, no idle runner pods consuming resources
- **Simplified operations**: No need to manage runner controller deployments or webhook servers

In this guide, we'll explore how to set up GitHub Actions to run on AWS CodeBuild using Terraform.

##### There are four main ways to run jobs on CodeBuild

1. **Runner on EC2**: The GitHub Actions runner installs directly on an EC2 instance. Simple but limited - many actions fail due to missing Node.js or build tools.

2. **Runner with Job Container**: The runner pulls a container image and executes the job inside it. Most flexible and compatible with existing workflows.

3. **Runner and Job in Same Container**: Uses a custom container image defined in `runs-on`. Requires the runner pre-installed in the image. Useful for specialized environments.

4. **Separate Runner and Job Containers**: Runner and job each run in their own containers. Adds complexity with limited benefit.

## Terraform Infrastructure

Let's build the complete infrastructure using Terraform. We'll create:
1. CodeBuild project
2. CodeConnection to GitHub
3. IAM roles and policies
4. CloudWatch log groups
5. VPC configuration (optional, for private network access)

### Prerequisites

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

### Variables

```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "github-actions-runner"
}

variable "compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  # Options: BUILD_GENERAL1_SMALL, BUILD_GENERAL1_MEDIUM, BUILD_GENERAL1_LARGE, BUILD_GENERAL1_2XLARGE
}

variable "runner_labels" {
  description = "Labels for the GitHub Actions runner"
  type        = list(string)
  default     = ["codebuild", "aws"]
}

variable "enable_privileged_mode" {
  description = "Enable privileged mode (required for Docker operations)"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for CodeBuild (optional, for private network access)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for CodeBuild (optional)"
  type        = list(string)
  default     = []
}

variable "environment_variables" {
  description = "Additional environment variables"
  type        = map(string)
  default     = {}
}
```

### IAM Roles and Policies

```hcl
# iam.tf
# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codebuild-role"
  }
}

# Basic policies for CodeBuild
resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.codebuild_logs.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection"
        ]
        Resource = [
          aws_codestarconnections_connection.github.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# VPC access policy (if VPC is configured)
resource "aws_iam_role_policy" "codebuild_vpc_policy" {
  count = var.vpc_id != "" ? 1 : 0
  role  = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeVpcs",
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional policy for Docker operations (if privileged mode is enabled)
resource "aws_iam_role_policy" "codebuild_docker_policy" {
  count = var.enable_privileged_mode ? 1 : 0
  role  = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### CodeConnection (GitHub Integration)

```hcl
# codeconnection.tf
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github-connection"
  provider_type = "GitHub"

  tags = {
    Name = "${var.project_name}-github-connection"
  }
}

# Note: After creating the connection, you must manually complete the 
# OAuth handshake in the AWS Console or using the AWS CLI
# aws codestar-connections update-connection-status \
#   --connection-arn <connection-arn> \
#   --status AVAILABLE
```

### CloudWatch Logs

```hcl
# logs.tf
resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-logs"
  }
}
```

### Security Group (for VPC configuration)

```hcl
# security_group.tf
resource "aws_security_group" "codebuild" {
  count       = var.vpc_id != "" ? 1 : 0
  name        = "${var.project_name}-codebuild-sg"
  description = "Security group for CodeBuild GitHub Actions runner"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project_name}-codebuild-sg"
  }
}
```

### CodeBuild Project

```hcl
# codebuild.tf
resource "aws_codebuild_project" "github_actions_runner" {
  name          = var.project_name
  description   = "GitHub Actions runner on AWS CodeBuild"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 60 # minutes

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.compute_type
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = var.enable_privileged_mode

    # Environment variables
    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild_logs.name
      status     = "ENABLED"
    }
  }

  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.vpc_id != "" ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = [aws_security_group.codebuild[0].id]
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_org}/${var.github_repo}.git"
    git_clone_depth = 0
    buildspec       = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "GitHub Actions runner will handle the build"
    EOT
  }

  tags = {
    Name = var.project_name
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

# GitHub Actions integration
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "CODECONNECTIONS"
  server_type = "GITHUB"
  token       = aws_codestarconnections_connection.github.arn
}
```

### Outputs

```hcl
# outputs.tf
output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.github_actions_runner.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.github_actions_runner.arn
}

output "codeconnection_arn" {
  description = "ARN of the CodeConnection (needs manual activation)"
  value       = aws_codestarconnections_connection.github.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild_role.arn
}

output "runner_labels" {
  description = "Labels to use in GitHub Actions runs-on"
  value       = var.runner_labels
}

output "setup_instructions" {
  description = "Instructions to complete the setup"
  value       = <<-EOT
    
    1. Activate the CodeConnection:
       aws codestar-connections update-connection-status \
         --connection-arn ${aws_codestarconnections_connection.github.arn} \
         --status AVAILABLE
    
    2. In your GitHub repository, go to Settings > Secrets and Variables > Actions
       Add the following repository variable:
       - Name: AWS_CODEBUILD_PROJECT
       - Value: ${aws_codebuild_project.github_actions_runner.name}
    
    3. Use in your workflow:
       runs-on: ${join(", ", var.runner_labels)}
  EOT
}
```

### Example terraform.tfvars

```hcl
# terraform.tfvars.example
aws_region   = "us-east-1"
github_org   = "your-github-org"
github_repo  = "your-repo"
project_name = "my-github-runner"

compute_type = "BUILD_GENERAL1_SMALL"

runner_labels = ["codebuild", "aws", "self-hosted"]

enable_privileged_mode = true

# Optional: For private network access
# vpc_id     = "vpc-xxxxx"
# subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]

environment_variables = {
  "AWS_DEFAULT_REGION" = "us-east-1"
  "DOCKER_BUILDKIT"    = "1"
}
```

## Deployment Steps

1. **Initialize Terraform**:
```bash
terraform init
```

2. **Review the plan**:
```bash
terraform plan
```

3. **Apply the configuration**:
```bash
terraform apply
```

4. **Activate the CodeConnection**:
```bash
aws codestar-connections update-connection-status \
  --connection-arn <connection-arn-from-output> \
  --status AVAILABLE
```

5. **Complete OAuth in AWS Console**:
   - Go to AWS Console > Developer Tools > Connections
   - Click on your connection and complete the GitHub authorization

## Using in GitHub Actions

### Basic Example (Option 2: Runner with Job Container)

```yaml
name: Build with CodeBuild

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: [codebuild, aws, self-hosted]
    
    container:
      image: node:18-alpine
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Install dependencies
        run: npm install
      
      - name: Run tests
        run: npm test
      
      - name: Build
        run: npm run build
```

### Advanced Example with Custom Runner Image (Option 3)

```yaml
name: Build with Custom Runner

on:
  push:
    branches: [main]

jobs:
  build:
    # Custom runner image with GitHub Actions runner pre-installed
    runs-on: 
      - image:custom-linux-public.ecr.aws/myaccount/my-runner:latest
      - BUILD_GENERAL1_MEDIUM
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Build with Docker
        run: |
          docker build -t myapp:latest .
          docker push myapp:latest
```

### Example with AWS Credentials

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: [codebuild, aws, self-hosted]
    
    container:
      image: amazon/aws-cli:latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      # CodeBuild automatically has AWS credentials via IAM role
      - name: Deploy to S3
        run: |
          aws s3 sync ./dist s3://my-bucket/
      
      - name: Invalidate CloudFront
        run: |
          aws cloudfront create-invalidation \
            --distribution-id XXXXX \
            --paths "/*"
```

## Important Considerations

### Cost Management

⚠️ **Warning**: Jobs can override the compute size via `runs-on`, potentially spinning up expensive `72xlarge` instances. Monitor your CodeBuild usage and set up billing alerts.

**Example of dangerous override**:
```yaml
runs-on:
  - codebuild
  - BUILD_GENERAL1_XLARGE  # Can be changed by any contributor!
```

**Mitigation strategies**:
1. Use AWS Budgets and billing alerts
2. Monitor CodeBuild usage with CloudWatch
3. Implement approval workflows for large compute sizes
4. Use branch protection rules

### GitHub Actions Compatibility

When using container images:
- GitHub mounts several folders automatically
- The `HOME` environment variable is overridden
- This can break tools expecting config files in `~`

**Workaround**:
```yaml
steps:
  - name: Fix HOME variable
    run: echo "HOME=/root" >> $GITHUB_ENV
```

### Docker Socket Access

- The Docker socket is automatically mounted when using job containers
- For the runner container, enable `privileged_mode` in the CodeBuild project

### Private Container Images

For ECR authentication:
1. Ensure IAM role has ECR permissions (included in our Terraform)
2. Use buildspec override for `docker login`, or
3. Configure credentials in the job definition

## Monitoring and Troubleshooting

### CloudWatch Logs

View logs in CloudWatch:
```bash
aws logs tail /aws/codebuild/my-github-runner --follow
```

### Common Issues

**1. Actions fail with "Node.js not found"**
- Use a container image with Node.js (Option 2)
- Or use a runner image with dependencies (Option 3)

**2. Docker commands fail**
- Enable `privileged_mode` in CodeBuild project
- Ensure Docker is available in the container image

**3. AWS credentials not working**
- Verify IAM role permissions
- Check if VPC configuration is blocking access
- Reset HOME environment variable if using custom images

**4. Connection timeout during npm install**
- Check VPC security group rules
- Ensure NAT gateway is configured for private subnets
- Verify DNS resolution

## Best Practices

1. **Use specific compute sizes**: Define appropriate default sizes in Terraform
2. **Enable CloudWatch logging**: Essential for debugging
3. **Use VPC for private access**: Connect to private resources securely
4. **Cache dependencies**: Use CodeBuild cache for faster builds
5. **Tag everything**: Use consistent tagging for cost allocation
6. **Rotate secrets regularly**: Use AWS Secrets Manager for sensitive data
7. **Monitor costs**: Set up AWS Budgets and cost anomaly detection
8. **Use multiple runners**: Create different runners for different workloads

## Conclusion

Running GitHub Actions on AWS CodeBuild provides a powerful and flexible CI/CD solution with full control over your build environment. With Terraform, you can version control your infrastructure and easily replicate runners across multiple repositories or environments.

The combination of CodeBuild's dynamic provisioning and GitHub Actions' ecosystem creates an efficient workflow that scales with your needs while maintaining security and cost control.

## References

- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Philipp Garbe's Blog: GitHub Actions and AWS CodeBuild](https://garbe.io/blog/2025/07/28/github-actions-codebuild/)
- [AWS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

*Have questions or suggestions? Feel free to reach out or leave a comment below!*

