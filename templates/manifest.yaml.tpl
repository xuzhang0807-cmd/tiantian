# TianTian Ops - Manifest Template
name: {{NAME}}
type: docker-web
domain: {{DOMAIN}}
created: '{{CREATED}}'
version: '1.0'

container:
  port: {{PORT}}

nginx:
  enabled: true
  cert_enabled: true

resources:
  cpu: 1
  memory: 512
