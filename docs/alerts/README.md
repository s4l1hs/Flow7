# Prometheus rules & Alertmanager integration for Flow7

This document explains how to add the Flow7 alert rules (`docs/alerts/prometheus_rules.yml`) into your Prometheus and configure Alertmanager receivers.

1) Place rules file on Prometheus server

- Copy `docs/alerts/prometheus_rules.yml` to a location accessible by Prometheus (e.g. `/etc/prometheus/rules/flow7.rules.yml`).

2) Reference the rule file from Prometheus config

In your Prometheus `prometheus.yml` add a `rule_files` entry, for example:

```yaml
rule_files:
  - 'rules/*.yml'
# Or explicitly:
  - '/etc/prometheus/rules/flow7.rules.yml'
```

After editing the config either restart Prometheus or use the `/-/reload` endpoint to reload config:

```bash
curl -X POST http://<prometheus-host>:9090/-/reload
```

3) Configure Alertmanager

- Add receivers (email, Slack, PagerDuty, etc.) to `alertmanager.yml` and match routing rules to `severity: page` or `severity: ticket` labels used by these rules.

Example minimal `alertmanager.yml` snippet for Slack:

```yaml
route:
  receiver: 'slack-critical'
receivers:
  - name: 'slack-critical'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/..../..../..'
        channel: '#alerts'
```

4) Test rules and alerts

- Use `promtool` to check rule syntax:
  ```bash
  promtool check rules /etc/prometheus/rules/flow7.rules.yml
  ```

- Trigger a test alert (increase a counter) or use the Alertmanager UI to send a test alert to receivers.

5) Recommended alerting responsibilities

- `severity=page`: Pager duty / on-call — immediate action required (DB down, scheduler job errors)
- `severity=ticket`: Create a ticket for later investigation (migration failures, high FCM failure rate as warning threshold)

Notes
- If Prometheus runs inside Kubernetes, mount the rule file using a ConfigMap. For example:
  - Create ConfigMap from the rules file: `kubectl create configmap flow7-prom-rules --from-file=prometheus_rules.yml=docs/alerts/prometheus_rules.yml` and mount it into the Prometheus server config directory.

If you want I can generate a ConfigMap manifest and a small GitHub Actions step to push rules into a cluster automatically.
