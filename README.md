# The Cost of Validation: Adding Governance Without Creating Bottlenecks

AWS Community Day South Florida — Level 300 Talk + Live Demo

## Overview

This repository contains all the infrastructure, application code, and demo scripts
for the talk on adding observability to a production-like data pipeline without
introducing new bottlenecks.

## Architecture

```
API Gateway → Lambda (ingestion) → SQS → ECS Fargate (processor) → DynamoDB
                                                ↓
                                         S3 (data lake raw)
```

The demo deliberately introduces a latency bottleneck in the ECS processor
(synchronous external API call inside the processing loop), then shows how
AWS X-Ray + ADOT reveals the exact source of latency — reducing p99 from ~8s to ~400ms.

## Stack

| Layer        | Service                        |
|--------------|-------------------------------|
| API          | API Gateway + Lambda (Python) |
| Queue        | SQS                           |
| Processing   | ECS Fargate (Python)          |
| Storage      | DynamoDB + S3                 |
| Traces       | AWS X-Ray + ADOT              |
| Metrics      | CloudWatch Metrics (EMF)      |
| Logs         | CloudWatch Logs (structured)  |
| Alerts       | CloudWatch Alarms + SNS       |
| IaC          | Terraform                     |

## Region

`us-east-2` (Ohio)

## Repository Structure

```
.
├── terraform/
│   ├── modules/          # Reusable modules per service
│   └── envs/demo/        # Demo environment root
├── app/
│   ├── ingestion/        # Lambda function code
│   └── processor/        # ECS Fargate processor code
├── observability/
│   ├── dashboards/       # CloudWatch dashboard definitions
│   └── alarms/           # Alarm configurations
├── demo-backup/          # Python scripts for backup demo
├── docs/adr/             # Architecture Decision Records
└── slides/               # Talk slide notes and references
```

## ADRs

- [ADR-001](docs/adr/ADR-001-otel-vs-native.md) — OpenTelemetry vs AWS-native only
- [ADR-002](docs/adr/ADR-002-sampling-strategy.md) — Sampling strategy
- [ADR-003](docs/adr/ADR-003-structured-logging.md) — Structured logging schema
- [ADR-004](docs/adr/ADR-004-alerting-thresholds.md) — Alerting & avoiding alert fatigue

## Demo Flow

1. `terraform apply` — provision all infrastructure
2. Send load without observability → silent latency problem
3. Enable ADOT instrumentation → X-Ray reveals the bottleneck
4. CloudWatch Insights query → find the error in structured logs
5. Alarm fires → SNS notification → governance in action

## Quick Start

```bash
cd terraform/envs/demo
terraform init
terraform apply
```
