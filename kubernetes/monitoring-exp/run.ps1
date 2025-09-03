param(
  [string]$NS = "rfreire1409-dev"
)

function Save-Out([string]$name, [string]$content) {
  $ts = Get-Date -Format "yyyyMMdd-HHmmss"
  $file = "$($name)-$($ts).txt"
  $content | Out-File -Encoding utf8 $file
  Write-Host "Guardado: $file"
}

Write-Host "==> Aplicando base (Service + Deployment)..."
oc apply -f .\10-backend-base.yaml | Out-Null

Write-Host "==> ESCENARIO 1: 1 réplica, recursos limitados"
oc apply -f .\20-scenario1.yaml | Out-Null
oc rollout status deploy/backend -n $NS

$topBefore = oc adm top pods -n $NS --containers
Save-Out "scenario1-top-before" $topBefore

Write-Host "==> Lanzando carga (k6) - escenario 1"
oc apply -f .\30-k6-script-configmap.yaml | Out-Null
oc delete job k6-scenario1 -n $NS --ignore-not-found | Out-Null
oc apply -f .\31-k6-job-scenario1.yaml | Out-Null
oc wait --for=condition=complete job/k6-scenario1 -n $NS --timeout=600s

$topAfter = oc adm top pods -n $NS --containers
Save-Out "scenario1-top-after" $topAfter

$k6pod = oc get pods -n $NS -l job-name=k6-scenario1 -o name
$k6logs = oc logs $k6pod -n $NS
Save-Out "scenario1-k6-logs" $k6logs

Write-Host "==> ESCENARIO 2: 3 réplicas, más recursos, co-localizadas"
oc apply -f .\21-scenario2.yaml | Out-Null
oc rollout status deploy/backend -n $NS

$topBefore2 = oc adm top pods -n $NS --containers
Save-Out "scenario2-top-before" $topBefore2

Write-Host "==> Lanzando carga (k6) - escenario 2"
oc delete job k6-scenario2 -n $NS --ignore-not-found | Out-Null
oc apply -f .\32-k6-job-scenario2.yaml | Out-Null
oc wait --for=condition=complete job/k6-scenario2 -n $NS --timeout=600s

$topAfter2 = oc adm top pods -n $NS --containers
Save-Out "scenario2-top-after" $topAfter2

$k6pod2 = oc get pods -n $NS -l job-name=k6-scenario2 -o name
$k6logs2 = oc logs $k6pod2 -n $NS
Save-Out "scenario2-k6-logs" $k6logs2

Write-Host "==> Listo. Revisa los archivos scenario*-*.txt para tu informe."
