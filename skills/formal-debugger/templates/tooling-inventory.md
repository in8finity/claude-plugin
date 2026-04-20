# Tooling Inventory — Template

Copy this file into your project's `investigations/` directory as `tooling-inventory.md`
and fill in the sections relevant to your stack. The formal-debugger skill reads this file
at Step 0a to avoid re-asking about tools every investigation.

Persistent record of available data collection tools, access methods, and query patterns.
Update this file as tooling changes (new dashboards, rotated credentials, new environments).

Claude: read the project's `tooling-inventory.md` at the start of every investigation
instead of asking the user to re-enumerate their tooling. Only ask about tools NOT listed
here or when access may have changed (e.g., credentials rotated, new environment).

## Production Database Access

<!-- Example entry:
### Orders DB (PostgreSQL)
- **Access**: `psql -h read-replica.internal -U readonly -d orders`
- **Read-only**: yes (replica)
- **Schemas**: public, billing, audit
- **Useful tables**: orders, order_items, payments, refunds
- **Audit trail**: audit.order_changes (has updated_at, changed_by, old_value, new_value)
- **Notes**: 30-day retention on replica; for older data use data warehouse
-->

## Production Logs

<!-- Example entry:
### Application Logs
- **Tool**: Datadog / `dd-logs` CLI
- **Query**: `dd-logs search --service=api --status=error --from=1h`
- **Retention**: 15 days hot, 90 days archive
- **Structured fields**: service, level, trace_id, user_id, request_id
- **Notes**: Logs are sampled at 10% for debug level; error/warn are 100%

### Request Traces
- **Tool**: Jaeger UI at https://jaeger.internal
- **Sampling**: 1% head-based sampling
- **Notes**: Traces older than 7 days only in cold storage (ask SRE)
-->

## Metrics / Dashboards

<!-- Example entry:
### API Latency Dashboard
- **URL**: https://grafana.internal/d/api-latency
- **Tool**: Grafana + Prometheus
- **Key metrics**: http_request_duration_seconds, error_rate_5xx
- **Alerting**: PagerDuty for p99 > 500ms
-->

## Error Tracking

<!-- Example entry:
### Sentry
- **URL**: https://sentry.io/org/mycompany/issues/
- **Projects**: api-server, web-frontend, mobile-ios
- **Notes**: Source maps uploaded on deploy; breadcrumbs include last 5 API calls
-->

## Runtime Access

<!-- Example entry:
### Staging API
- **Base URL**: https://api.staging.internal
- **Auth**: Bearer token from `vault read secret/staging/api-token`
- **Notes**: Staging data resets weekly from anonymized prod snapshot

### Production API
- **Access**: Firewalled; need VPN + `curl` from bastion host
- **Command**: `ssh bastion -- curl -s https://api.prod.internal/health`
-->

## Config / Feature Flags

<!-- Example entry:
### LaunchDarkly
- **Dashboard**: https://app.launchdarkly.com/myproject
- **CLI**: `ldcli flags list --project=myproject --environment=production`
- **Audit log**: Settings > Audit log (shows who changed what flag when)
- **Notes**: Flag changes propagate in ~30s; check evaluation count for impact

### Environment Variables
- **Where**: Kubernetes ConfigMaps in `prod` namespace
- **Command**: `kubectl get configmap api-config -n prod -o yaml`
-->

## Queue / Message Systems

<!-- Example entry:
### SQS Queues
- **Dashboard**: AWS Console > SQS > us-east-1
- **Key queues**: order-processing, notification-dispatch, webhook-retry
- **DLQ monitoring**: CloudWatch alarm on ApproximateNumberOfMessagesVisible > 0
- **CLI**: `aws sqs get-queue-attributes --queue-url=... --attribute-names=All`
-->

## CI/CD and Deploy History

<!-- Example entry:
### GitHub Actions
- **Repo**: github.com/mycompany/api-server
- **Deploy workflow**: `.github/workflows/deploy.yml`
- **Deploy history**: `gh run list --workflow=deploy.yml --limit=10`
- **Currently deployed**: `kubectl get deployment api -n prod -o jsonpath='{.spec.template.metadata.labels.version}'`
-->

## Skills and Scripts

<!-- Example entry:
### Data Export Script
- **Location**: `scripts/export_user_data.py`
- **Usage**: `python scripts/export_user_data.py --user-id=123 --format=json`
- **Notes**: Read-only; queries replica DB

### Log Search Skill
- **Skill**: `/search-logs`
- **Usage**: `/search-logs --service=api --level=error --since=2h`
-->

## Access Constraints

<!-- Example entry:
- Production DB writes require approval from DBA team (Slack #dba-requests)
- PII queries require data-access ticket (JIRA DATA-xxx)
- Logs older than 15 days: ask SRE to restore from archive (~2h turnaround)
- Mobile app builds: check App Store Connect / Google Play Console (marketing@company has access)
-->
