# AWS DevOps Engineer Assessment – Unleash Live

This repository contains an Infrastructure-as-Code implementation for the **Unleash Live AWS DevOps Engineer technical assessment**.

The project demonstrates a **multi-region AWS architecture deployed via Terraform**, including authentication, serverless compute, container workloads, and CI/CD automation.

---

# Architecture Overview

The system is deployed in **two regions**:

- us-east-1
- eu-west-1

Authentication is centralized in **us-east-1 using Amazon Cognito**, while the compute stack runs in both regions.

```
                Cognito (us-east-1)
                       │
                       ▼
                API Gateway (JWT Auth)
                 /greet        /dispatch
                    │             │
                    ▼             ▼
             Lambda Greeter   Lambda Dispatcher
                 │                 │
                 ▼                 ▼
            DynamoDB Table      ECS Fargate
                 │                 │
                 └──────► SNS Topic ◄───────┘
```

---

# Services Used

This project uses the following AWS services:

- Amazon Cognito – authentication for API endpoints
- API Gateway (HTTP API) – secure API layer
- AWS Lambda – serverless compute
- Amazon DynamoDB – regional data storage
- Amazon ECS (Fargate) – container execution
- Amazon SNS – verification messaging
- CloudWatch Logs – observability
- Terraform – infrastructure as code
- GitHub Actions – CI/CD automation

---

# Repository Structure

```
aws-assessment
│
├── infra
│   ├── main.tf
│   ├── providers.tf
│   ├── variables.tf
│   │
│   └── modules
│       ├── auth
│       │   └── main.tf
│       │
│       └── compute
│           ├── main.tf
│           ├── variables.tf
│           │
│           ├── lambda_greeter
│           │   └── app.py
│           │
│           └── lambda_dispatcher
│               └── app.py
│
├── tests
│   └── run.py
│
└── .github
    └── workflows
        └── deploy.yml
```

---

# Infrastructure Deployment

## 1. Prerequisites

Install the following tools:

- Terraform ≥ 1.5
- AWS CLI
- Python 3.10+

Configure AWS credentials:

```bash
aws configure
```

---

## 2. Deploy Infrastructure

Navigate to the infrastructure directory:

```bash
cd infra
```

Initialize Terraform:

```bash
terraform init
```

Preview the infrastructure plan:

```bash
terraform plan
```

Apply the deployment:

```bash
terraform apply
```

Terraform will provision:

- Cognito user pool
- API Gateway
- Lambda functions
- DynamoDB tables
- ECS cluster and Fargate task
- VPC networking
- IAM roles and policies

---

# Cognito Test User

Create a test user using AWS CLI:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <POOL_ID> \
  --username "your_email@example.com" \
  --user-attributes Name=email,Value="your_email@example.com" \
  --message-action SUPPRESS
```

Set a permanent password:

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id <POOL_ID> \
  --username "your_email@example.com" \
  --password 'YourStrongPassword123!' \
  --permanent
```

---

# Running the Test Script

The automated test script:

- Authenticates against Cognito
- Retrieves a JWT token
- Calls `/greet` in both regions concurrently
- Calls `/dispatch` in both regions
- Measures and prints request latency

Install dependencies:

```bash
pip install boto3 httpx
```

Set required environment variables:

```bash
export COGNITO_CLIENT_ID=<client_id>
export COGNITO_USERNAME=<email>
export COGNITO_PASSWORD=<password>

export API_URL_US=$(terraform -chdir=infra output -raw api_url_us)
export API_URL_EU=$(terraform -chdir=infra output -raw api_url_eu)
```

Run the test:

```bash
python tests/run.py
```

Example output:

```
/greet us-east-1 -> 200 (85 ms)
/greet eu-west-1 -> 200 (170 ms)

dispatch us-east-1 -> 200
dispatch eu-west-1 -> 200
```

---

# Multi-Region Deployment Strategy

Terraform modules are used to deploy the same compute stack into two regions.

Two AWS providers are defined:

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
}
```

The compute module is instantiated twice:

```hcl
module "compute_us"
module "compute_eu"
```

This ensures identical infrastructure in both regions.

---

# CI/CD Pipeline

The repository includes a GitHub Actions workflow.

Pipeline stages:

1. Terraform format validation
2. Terraform validation
3. Security scanning using **tfsec**
4. Terraform plan
5. Placeholder for automated test execution

Workflow file:

```
.github/workflows/deploy.yml
```

---

# Cost Optimization

To minimize AWS costs:

- ECS tasks run in **public subnets**
- No NAT gateway is used
- DynamoDB uses **PAY_PER_REQUEST**
- ECS tasks are short-lived containers

---

# Cleanup

Destroy all resources after testing to avoid ongoing AWS charges:

```bash
terraform destroy
```

---

# Verification

Successful execution will trigger SNS messages containing:

```json
{
 "email": "<candidate email>",
 "source": "Lambda | ECS",
 "region": "<executing region>",
 "repo": "<github repository>"
}
```

These messages are used by the Unleash Live team to automatically verify the assessment.

---

# Author

AWS DevOps Engineer Assessment  
Candidate: **Joseph Akkawi**
Email: **joseph.akkawi98@gmail.com**

