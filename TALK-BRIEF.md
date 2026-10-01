# TALK BRIEF — Community Day South Florida
## The Cost of Validation: Adding Governance Without Creating Bottlenecks

**Fecha límite:** 10 días desde hoy  
**Duración:** 40 min + 5 min Q&A  
**Nivel:** 300  
**Idioma:** Inglés  
**Speaker:** Data Engineer / Platform Engineering specialization  
**Región AWS:** us-east-2 (Ohio)

---

## ESTRUCTURA DE LA CHARLA

### Hook (3 min)
Apertura con confesión personal: "I broke production by adding observability."
El problema real: sin observabilidad estás ciego, con mala observabilidad creaste un nuevo cuello de botella.

### Act 1 — The Problem Space (7 min)
- Silent failures en producción: latency drift, data quality decay, queue depth spiral
- Anti-patrones comunes: logs no estructurados, dashboards que nadie mira, alert fatigue
- La pregunta que organiza todo: ¿cómo agregamos observabilidad sin crear los problemas que queremos resolver?

### Act 2 — The Architecture Decisions (10 min)
Walkthrough de 4 ADRs con trade-offs honestos:
- ADR-001: OpenTelemetry (ADOT) vs AWS-native
- ADR-002: Sampling strategy (reservoir + rate + tail-based errors)
- ADR-003: Structured logging con schema mandatorio
- ADR-004: Alerting en SLO burn rate, no en métricas crudas

### Act 3 — Live Demo (15 min)
3 fases:
1. Sistema con latency bug activo, sin observabilidad → p99 en ~8s, silencioso
2. ADOT habilitado → X-Ray muestra el span culpable en 30 segundos
3. Fix aplicado → p99 baja a ~400ms, con evidencia visual en el dashboard

### Wrap-up (5 min)
- Resumen de los 4 aprendizajes
- Línea de cierre: "Governance is a contract, not a checkpoint."
- GitHub repo con todo el código

---

## ARQUITECTURA DEL SISTEMA (DEMO)

```
API Gateway → Lambda (ingestion) → SQS → ECS Fargate (processor) → DynamoDB
                                               ↓
                                          S3 (raw data lake)

Observability layer:
ADOT Collector sidecar → X-Ray (traces) + CloudWatch (metrics + logs)
```

**El bottleneck de la demo:**
El ECS processor tiene una llamada síncrona a una "validation API" externa dentro del loop de procesamiento. Esto simula un anti-patrón real de producción. Con X-Ray, el span `external_validation` aparece como el segmento más costoso del waterfall — root cause en 30 segundos.

**Los dos toggles de demo (variables de Terraform):**
- `introduce_latency_bug = true/false` → activa/desactiva el bottleneck
- `enable_observability = true/false` → activa/desactiva ADOT

---

## STACK TECNOLÓGICO

| Capa | Servicio | Decisión |
|---|---|---|
| API | API Gateway HTTP + Lambda (Python 3.12) | Serverless, sin infra que gestionar |
| Cola | SQS + DLQ | Desacoplamiento, reintentos automáticos |
| Procesamiento | ECS Fargate (Python 3.12) | Containerizado, escalable |
| Storage | DynamoDB + S3 | Hot data + raw lake |
| Traces | AWS X-Ray vía ADOT | OTel standard, backend intercambiable |
| Métricas | CloudWatch Metrics (EMF) | Nativo, sin agente extra |
| Logs | CloudWatch Logs (JSON estructurado) | Queryable con Insights |
| Alertas | CloudWatch Alarms + SNS | SLO burn rate, dos tiers (P1/P2) |
| IaC | Terraform >= 1.6, provider AWS ~> 5.0 | Modules por servicio |

---

## ADRs — RESUMEN EJECUTIVO

### ADR-001: OpenTelemetry (ADOT) vs AWS-native only
**Decisión:** ADOT como capa de instrumentación, X-Ray y CloudWatch como backends.  
**Por qué:** Vendor-neutral. El código no sabe a dónde van los traces. Si mañana migramos de X-Ray a Datadog, solo cambia el collector config.  
**Trade-off aceptado:** Sidecar ADOT en ECS (+1 container). Lambda cold start +50ms con el layer.  
**Lo que NO elegimos:** AWS X-Ray SDK directamente (lock-in), third-party APM (costo + datos salen de AWS).

### ADR-002: Sampling strategy
**Decisión:** Reservoir (5 req/s siempre) + Rate (5% del resto) + 100% de errores vía tail-based sampling.  
**Por qué:** A 500 req/s, 100% sampling cuesta ~$270/mes y agrega 2-5ms por request. Con esta estrategia: ~$18/mes.  
**Clave:** La config vive en un YAML del collector — no en el código de la app. Cambiar el sampling no requiere redeploy de la app.  
**Lo que NO elegimos:** 100% (caro, agrega latencia), 1% fijo (puede perder todos los errores en periodos de bajo tráfico).

### ADR-003: Structured logging con schema mandatorio
**Decisión:** Shared logger (`app/shared/logger.py`) que todos los servicios importan. Campos mandatorios enforced en código.  
**Schema mandatorio:** `timestamp`, `level`, `service`, `environment`, `trace_id`, `span_id`, `request_id`, `message`, `duration_ms`.  
**Por qué:** `trace_id` propagado automáticamente desde OTel context. Un query en CloudWatch Insights correlaciona logs + traces de un request en segundos.  
**Lo que NO elegimos:** JSON sin schema (los field names divergen), logs no estructurados (no queryables a escala).

### ADR-004: Alerting en SLO burn rate
**Decisión:** Dos tiers de alertas basadas en consumo de error budget, no en métricas de infraestructura.  
**SLOs definidos:** Availability 99.5% (error rate < 0.5%) | Latency P99 < 1000ms.  
**P1 (page):** Error rate quema >5% del budget mensual en 1h → SNS → respuesta en 15 min.  
**P2 (ticket):** P99 > 2x baseline SLO por 10 min sostenidos → SNS → próximo día hábil.  
**Lo que NO alertamos:** CPU/memoria en aislamiento, queue depth solo, errores individuales bajo el threshold.  
**Resultado:** ~75% menos de alert volume vs alerting basado en thresholds estáticos.

---

## SLIDES — CONTENIDO (18 slides)

**Slide 1 — Title**
- Título: "The Cost of Validation: Adding Governance Without Creating Bottlenecks"
- Subtítulo: AWS Community Day South Florida
- Nombre + rol

**Slide 2 — Hook**
- Una sola línea grande centrada: *"I broke production by adding observability."*

**Slide 3 — The Silent Failure**
- Diagrama: pipeline con "✓ All good" y debajo "Data is wrong"
- Sin bullets, la historia la cuenta el speaker

**Slide 4 — The 3 Failure Modes**
- ① Latency drift → nobody notices until it's 10x
- ② Data quality decay → counts look right, values don't
- ③ Queue depth spiral → slow at first, then exponential

**Slide 5 — The Anti-Patterns**
- ✗ Unstructured logs → noise, not signal
- ✗ Dashboards nobody watches
- ✗ Alerts that always fire → learned ignorance

**Slide 6 — The Question**
- Una línea: *"How do we add observability without creating new bottlenecks?"*

**Slide 7 — Architecture Overview**
- Diagrama del sistema completo con la capa de observabilidad debajo

**Slide 8 — ADR-001: OTel vs Native**
- Tabla comparativa dos columnas: AWS X-Ray SDK vs ADOT
- Resaltar columna ganadora

**Slide 9 — ADR-002: Sampling**
- Diagrama visual de la estrategia de sampling
- Número de impacto: $270/mo → $18/mo

**Slide 10 — ADR-003: Structured Logging**
- Dos bloques lado a lado: Before (print) vs After (structured logger)
- Una línea: "CloudWatch Insights can query the After. Not the Before."

**Slide 11 — ADR-004: Alerting**
- Tabla: "Don't alert on" vs "Alert on"
- CPU/memoria/queue vs SLO burn rate/DLQ/P99

**Slide 12 — Pivot a demo**
- Línea grande: *"Governance is a contract, not a checkpoint."*

**Slide 13 — Demo Setup**
- Diagrama de arquitectura con los dos toggles visibles:
  `INTRODUCE_LATENCY_BUG = true / ENABLE_OBSERVABILITY = false`

**Slide 14 — Demo Evidence (backup)**
- Screenshot pre-capturado del X-Ray waterfall con anotación:
  `external_validation: 8,100ms ← here`
- Usar si algo falla en la demo en vivo

**Slide 15 — Demo: The Fix**
- Solo dos números: `p99: 8,400ms → 380ms`

**Slide 16 — What We Learned**
- ① Standard instrumentation → portability
- ② Smart sampling → signal without cost
- ③ Structured logs → queryable by design
- ④ SLO-based alerting → user impact, not noise

**Slide 17 — Closing**
- Misma línea del slide 12, más grande:
  *"Governance is a contract, not a checkpoint."*

**Slide 18 — Resources**
- GitHub repo link
- Nombre + LinkedIn/Twitter/email

---

## SCRIPT DE LA CHARLA

### OPENING (3 min)

Hey everyone. Thanks for being here.

I want to start with a confession.

Two years ago, I was the person who broke production. Not because I wrote bad code. Not because I skipped tests. I broke production because I added observability.

We had a data pipeline. It was working fine — well, "fine" meaning nobody was paging us at 3am, which in platform engineering counts as success. And then we got a mandate from the security team: "You need governance. You need visibility. You need to know what's happening in your pipeline at all times."

So we did what any responsible engineer does. We instrumented everything. We added tracing. We added metrics. We added logging on every function call. We added alerts on every metric.

And within two weeks, our p99 latency went from 400 milliseconds to 8 seconds.

We had created a new bottleneck. In the name of observability.

So today I want to talk about that. Not the happy path where you add observability and everything gets better. The real path — where the cure can be as bad as the disease, and the decisions you make upfront determine which one you get.

This is a level 300 talk. I'm going to show you architecture decisions, trade-offs, and a live demo where you can watch a pipeline fall apart — and then watch observability tell you exactly why.

Let's go.

---

### ACT 1 — THE PROBLEM SPACE (7 min)

Let me describe a scene that I guarantee at least half of you have lived.

It's a Tuesday. Your pipeline has been running for hours. Your downstream team sends you a Slack message: "Hey, our dashboard is showing stale data." You check your pipeline. It's green. All tasks completed successfully. No errors in the logs.

But the data is wrong.

This is what I call a silent failure. And it's the most expensive kind of failure there is — not because of the blast radius in the moment, but because of the time it takes to diagnose. You're not fixing a broken thing. You're finding a thing that doesn't know it's broken.

In a data pipeline without proper observability, there are three failure modes that will absolutely find you:

**First: Latency drift.** Your pipeline processes records in 400ms on Monday. By Friday it's at 4 seconds. Nobody noticed because nobody was watching, and the system never threw an error. It just slowed down. Like a car losing tire pressure on the highway.

**Second: Data quality degradation.** Records are being processed, counts look right, but the payload transformation has a silent bug. 3% of records have a null field that should have a value. Downstream, someone's ML model starts drifting. Three weeks later, someone figures out the training data was corrupted.

**Third: Cascading queue depth.** Your processor falls slightly behind — maybe 10%, maybe 20%. The queue grows. Slowly at first. Then exponentially. By the time you notice, you have 48 hours of backlog and a very unhappy SLA.

None of these scenarios throw an exception. None of them trigger your existing alerts. They are operationally invisible without the right instrumentation.

Now here's the thing. Most teams know this. So they add observability. And then they fall into a different set of traps.

The ones I see most often:

**Logging everything, unstructured.** It feels like observability. It's actually noise. When an incident happens at 2am, you open CloudWatch and you see 40,000 lines of text and no way to query them.

**Metrics nobody watches.** You set up a CloudWatch dashboard. It has 20 graphs. Nobody looks at it until something breaks. At which point it's not a dashboard — it's a crime scene.

**Alerts that always fire.** You set a threshold: alert if CPU goes above 70%. Your pipeline spikes to 75% CPU for 30 seconds every time a batch starts. Within a month, your team has trained themselves to ignore the alert channel.

This is alert fatigue. And it's not a human problem — it's a design problem.

So the question isn't "should we add observability?" The answer to that is obviously yes. The question is: how do we add it without creating the exact problems we're trying to solve?

That's what I want to show you today.

---

### ACT 2 — THE ARCHITECTURE DECISIONS (10 min)

When we redesigned our observability stack, we made every decision explicit. We documented them as Architecture Decision Records — ADRs. Not because we had to. Because when you're making trade-offs, you need receipts.

I'm going to walk you through four decisions that shaped everything else.

---

**ADR-001: OpenTelemetry versus going fully AWS-native.**

AWS has great native tooling: X-Ray SDK, CloudWatch agent, Lambda Insights. It works. It's well-documented. You can be up and running in an afternoon.

The problem is: it's AWS-shaped. If you instrument your code with the X-Ray SDK, your code has an opinion about where your traces go. Change your backend six months from now and you're re-instrumenting everything.

OpenTelemetry is the CNCF standard. Vendor-neutral. Your code emits signals; the collector decides where they go. We went with ADOT — AWS Distro for OpenTelemetry — because AWS manages it, so we get the reliability of a managed service with the portability of the open standard.

Trade-off we accepted: there's an ADOT sidecar running next to our ECS task. One more container to manage. We decided that was worth the portability. There's no free lunch. Make the trade-off explicit so you can revisit it later.

---

**ADR-002: How much do we sample?**

This is the one that bit us the first time around. We started at 100% sampling. Every single request traced. At 500 requests per second, that's roughly $270 a month just in X-Ray storage. And the tracing overhead itself added 2 to 5 milliseconds per request. We were making the system slower in order to observe it.

We went with reservoir plus rate sampling. Five requests per second always sampled. Five percent of everything above that. And here's the key part: 100% of errors and slow requests are always captured via tail-based sampling in the ADOT collector.

The math: $270/month down to $18/month. And we captured more actionable signal — because we focused the capture budget on the things that actually matter.

The config lives in a YAML file in the collector. No code changes to adjust it. That's governance that doesn't create bottlenecks.

---

**ADR-003: Structured logging with a mandatory schema.**

Everyone says "use structured logging." But there's a gap between "emit JSON" and "emit queryable, consistently-schemed JSON."

We built a shared logger — one Python module — that all services import. It enforces mandatory fields: timestamp, level, service name, environment, trace ID, request ID, message. The trace ID comes from OTel context propagation automatically. Nobody has to remember to add it.

Why does this matter? Because when something breaks, I can open CloudWatch Logs Insights and type:

```sql
filter trace_id = "1-abc123-..."
| fields timestamp, service, level, message
| sort timestamp asc
```

And I get the complete story of one request across Lambda and ECS, in chronological order, correlated with the X-Ray trace. That's the difference between finding a bug in 3 minutes and finding it in 3 hours.

---

**ADR-004: Don't alert on metrics. Alert on SLO burn rate.**

Instead of "alert when CPU > 70%", we define SLOs first:
- 99.5% of requests succeed
- P99 latency under 1 second

Then we alert when we're burning through our error budget too fast. If we're on track to consume 5% of our monthly error budget in a single hour — that's a P1. Page someone. If P99 latency is 2x above the SLO baseline for 10 sustained minutes — that's a P2. Create a ticket.

What we do NOT alert on: CPU, memory, queue depth in isolation. These are implementation details. The SLO is the contract with the user.

Result: we reduced alert volume by about 75%. And every alert that fires now means something real.

---

Four decisions. Each one a trade-off. Each one documented. That's what governance looks like when it's done right — not as a checkpoint, but as a contract.

---

### ACT 3 — LIVE DEMO (15 min)

*[Switch to terminal / AWS console]*

The architecture is: API Gateway receives HTTP POST requests, Lambda validates and enqueues to SQS, ECS Fargate processor polls the queue, writes to DynamoDB and S3, and the ADOT collector sidecar exports traces to X-Ray and metrics to CloudWatch.

Everything was provisioned with Terraform. One `terraform apply`.

**Phase 1: The broken system**

Let me turn on the latency bug — this simulates a real pattern: a synchronous call to an external validation service inside the processing loop.

*[Send 50 requests, show dashboard — p99 at ~8s]*

P99 latency: 8 seconds. No errors. The system thinks it's healthy. This is the silent latency drift I was describing earlier.

**Phase 2: What does X-Ray show us?**

*[Enable ADOT, send same load, open X-Ray trace map]*

Look at this. Every node is a service. Every edge is a call. And that thick line right there — that's the `external_validation` span inside `process_record`.

*[Click into single trace — show waterfall]*

Here's one request. SQS receive: 20ms. DynamoDB write: 12ms. S3 write: 18ms. `external_validation`: 8,100ms.

One span. One function call. Eight seconds. Root cause identified in 30 seconds, without reading a single line of code.

**Phase 3: The fix — and proving it worked**

*[Set introduce_latency_bug=false, send same 50 requests]*

P99: 380 milliseconds. Same load. Same infrastructure. One configuration change.

And here's the part that matters for governance: we didn't just fix it. We have a trace that shows the before and after. We have structured logs that correlate the change. We have a CloudWatch dashboard that shows the drop. That's the audit trail. That's how you prove the fix actually worked.

**Phase 4: The alarm fires**

*[Show SNS notification]*

P2 alarm. "Lambda P99 latency above 3s for 10 minutes." With a link to the runbook.

Notice what the alarm does NOT say: "CPU utilization high." It says: your latency SLO is burning. That's a user-impacting statement. That's actionable.

---

### WRAP-UP (5 min)

We started with a system that was breaking silently. We added observability. And we almost made it worse.

The difference between observability that helps and observability that hurts comes down to four decisions:

**One:** Choose your instrumentation standard with portability in mind. ADOT today, whatever comes next tomorrow.

**Two:** Sample intelligently. 100% coverage of errors. Proportional coverage of success. Your budget will thank you.

**Three:** Make your logs queryable by design, not by accident. A shared logger is two hours of work that saves you hours per incident, forever.

**Four:** Alert on user impact, not implementation details. SLO burn rate, not CPU percentages.

Governance is not a gate at the end of a pipeline. It's not a compliance checkbox. It's a contract — between your system and the people who depend on it, between your current self and your future self debugging at 2am.

When governance is a checkpoint, it creates bottlenecks. When governance is a contract, it creates confidence.

The code, the Terraform, all four ADRs — they're all in the GitHub repo. Take it, break it, tell me what I got wrong.

Thank you.

---

### Q&A — RESPUESTAS PREPARADAS

**"Isn't ADOT overkill for a small team?"**
It's actually less overhead than you think — Lambda layer, ECS sidecar, done. The question isn't team size, it's: do you want to re-instrument everything when you switch backends? I'd rather pay 30 minutes of setup now.

**"How do you handle the ADOT sidecar failing?"**
The sidecar is non-essential in our task definition. If it crashes, the processor keeps running — you just lose traces temporarily. Observability cannot be in the failure path of the business logic.

**"What about cost at very high scale?"**
That's exactly why ADR-002 exists. At 50k req/s you revisit the sampling math. The framework scales, the numbers change.

**"Can you show me the Terraform?"**
Yes — repo link is right there, everything is modular. `terraform apply` and you have the full stack.

---

## REPOSITORIO — ESTADO ACTUAL

**Ubicación:** `~/observability-talk/`  
**Cuenta AWS:** 748607162458 | Región: us-east-2

### Archivos creados (42 archivos)

```
observability-talk/
├── README.md
├── .gitignore
├── build-and-push.sh          ← buildea imagen processor y pushea a ECR
├── app/
│   ├── shared/
│   │   └── logger.py          ← shared structured logger (ADR-003)
│   ├── ingestion/
│   │   ├── handler.py         ← Lambda function
│   │   └── requirements.txt
│   └── processor/
│       ├── main.py            ← ECS processor con el latency bug
│       ├── Dockerfile
│       └── requirements.txt
├── terraform/
│   ├── envs/demo/
│   │   ├── main.tf            ← root module, wires everything
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── modules/
│       ├── vpc/               ← 2 public + 2 private subnets, NAT
│       ├── api_gateway/       ← HTTP API v2
│       ├── lambda/            ← ingestion function + ADOT layer
│       ├── sqs/               ← queue + DLQ
│       ├── ecs/               ← Fargate cluster + task + service
│       ├── dynamodb/          ← PAY_PER_REQUEST + TTL + PITR
│       ├── s3/                ← raw data bucket + encryption
│       └── observability/     ← log groups, SNS, alarms, dashboard
└── docs/adr/
    ├── ADR-001-otel-vs-native.md
    ├── ADR-002-sampling-strategy.md
    ├── ADR-003-structured-logging.md
    └── ADR-004-alerting-thresholds.md
```

### Pendiente de crear
- `demo-backup/` — scripts Python para ejecutar demo sin live coding
- `slides/` — notas de referencia por slide
- `terraform/envs/demo/terraform.tfvars` — copiar del .example y completar email
- ECR repository para la imagen del processor

---

## PLAN DE 10 DÍAS

| Día | Tarea |
|-----|-------|
| 1 (hoy) | ✅ Repo + Terraform + App code + ADRs + Script de charla |
| 2 | Crear ECR → build-and-push.sh → terraform apply → validar infra |
| 3 | Probar flujo completo end-to-end (POST → DynamoDB + S3) |
| 4 | Validar X-Ray traces + CloudWatch Insights queries |
| 5 | Script demo backup en Python + load generator |
| 6 | Rehearsal completo de la demo (timing) |
| 7 | Slides en template oficial Community Day |
| 8 | Ensayo completo charla + demo (40 min) |
| 9 | Ajustes post-ensayo + screenshots para slides backup |
| 10 | Freeze — solo fix de bugs críticos, no cambios de contenido |

---

## PRÓXIMOS PASOS INMEDIATOS (Día 2)

```bash
# 1. Copiar y editar tfvars
cp ~/observability-talk/terraform/envs/demo/terraform.tfvars.example \
   ~/observability-talk/terraform/envs/demo/terraform.tfvars
# Editar: sns_alert_email = "tu-email@example.com"

# 2. Build y push de la imagen
cd ~/observability-talk
./build-and-push.sh

# 3. Terraform
cd ~/observability-talk/terraform/envs/demo
terraform init
terraform apply

# 4. Verificar outputs
terraform output
```

---

## LÍNEAS CLAVE DE LA CHARLA (para memorizar)

- **Apertura:** *"I broke production by adding observability."*
- **Pivot a demo:** *"Governance is a contract, not a checkpoint."*
- **Cierre:** *"When governance is a checkpoint, it creates bottlenecks. When governance is a contract, it creates confidence."*
- **El remate del X-Ray:** *"One span. One function call. Eight seconds. Root cause identified in 30 seconds, without reading a single line of code."*

---

*Documento generado: 2026-10-01 | Actualizar con cambios del día 2 en adelante*
