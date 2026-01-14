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

output "setup_instructions" {
  description = "Instructions to complete the codeconnection setup"
  value = trimspace(<<-EOF
Activate the CodeConnection:
  1. Go to: https://console.aws.amazon.com/codesuite/settings/connections
  2. Find connection: "gha-runner-connection" (Status: Pending)
  3. Click "Update pending connection"
  4. Sign in to GitHub and authorize the AWS Connector app
  5. Select the repositories to grant access
  6. Click "Connect"
EOF
  )
}
