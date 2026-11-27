# to-do-list-api

API de tareas en Flask. Las tareas se guardan en RDS MySQL. La instancia EC2, la base, el secret y las alarmas los crea Terraform. GitHub Actions prueba cada pull request, publica un release al etiquetar una versión y despliega ese zip en la EC2. CloudWatch muestra el CPU de la instancia, los errores de base de datos y las tareas creadas.

## Endpoints

La API escucha en el puerto 8000.

| Método | Ruta | Qué hace |
| --- | --- | --- |
| GET | `/tasks` | Lista las tareas |
| POST | `/tasks` | Crea una tarea. Cuerpo: `{"title": "...", "done": false}` |
| GET | `/version` | Devuelve `APP_VERSION` |
| GET | `/health` | Prueba la conexión a MySQL y devuelve `OK` o `FAIL`, la versión y un timestamp |

Ejemplo, con la IP que imprime Terraform:

```bash
curl -X POST "http://<ip>:8000/tasks" \
  -H "Content-Type: application/json" \
  -d '{"title": "estudiar para el examen", "done": false}'

curl "http://<ip>:8000/tasks"
curl "http://<ip>:8000/version"
curl "http://<ip>:8000/health"
```

## Pruebas en local

No hace falta AWS. Las pruebas simulan la base y CloudWatch.

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r src/requirements.txt pytest
.venv/Scripts/python -m pytest
```

En WSL el intérprete del venv es `.venv/bin/python`.

## Secrets del repositorio

GitHub Actions no ve el `aws configure` de WSL. En **Settings → Secrets and variables → Actions** tienen que existir:

| Secret | De dónde sale |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | `aws configure get aws_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | `aws configure get aws_secret_access_key` |
| `AWS_SESSION_TOKEN` | `aws configure get aws_session_token` |
| `ALERT_EMAIL` | El correo que recibe las alarmas |
| `EC2_SSH_KEY` | El contenido de `terraform/todo-list-api.pem`, después del primer apply |

Las tres llaves de AWS son de la sesión del Learner Lab. Cuando el lab se reinicia, hay que volver a pegarlas. `ci` no las usa.

`main` exige pull request y el check `ci`. Un push directo a `main` lo rechaza el ruleset.

## Crear la infraestructura

La instancia, al arrancar, clona este repositorio, instala `src/requirements.txt` y levanta `todo-api.service`. No hace falta entrar por SSH ni copiar archivos con scp.

Desde GitHub: **Actions → provision → Run workflow**. El workflow crea el bucket de estado si no existe, aplica el stack y muestra la IP y las URLs.

Desde WSL, con la sesión del lab activa:

```bash
cd terraform/bootstrap
terraform init
terraform apply

cd ..
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
terraform init -input=false \
  -backend-config="bucket=todo-list-tfstate-${ACCOUNT}" \
  -backend-config="key=todo-list-api/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=todo-list-tfstate-lock" \
  -backend-config="encrypt=true"

export TF_VAR_alert_email="tu-correo@ejemplo.com"
terraform apply
```

El bootstrap crea el bucket con la AWS CLI. El Learner Lab niega `s3:GetBucketObjectLockConfiguration`, y el recurso `aws_s3_bucket` de Terraform falla al leerla aunque el bucket ya exista. El tfstate del stack queda en `s3://todo-list-tfstate-<account-id>/todo-list-api/terraform.tfstate`. No se sube al repositorio. El bucket vive en el Learner Lab: cuando el sandbox se destruye, hay que volver a correr el bootstrap.

Después del apply llega un correo de AWS para confirmar la suscripción SNS. Sin esa confirmación las alarmas no avisan.

## Destruir la infraestructura

**Actions → destroy → Run workflow**, o en WSL, dentro de `terraform/`:

```bash
export TF_VAR_alert_email="tu-correo@ejemplo.com"
terraform destroy
```

Eso borra la EC2, RDS, el secret y las alarmas. El bucket del tfstate se queda, para poder ver el state en S3.

## Entrega continua

Con los workflows ya en `main`:

```bash
git checkout main
git pull
git tag v1.0.0
git push origin v1.0.0
```

El tag crea un GitHub Release con `to-do-list-api.zip`. Al publicarse, el workflow de deploy copia ese zip a la EC2, reinicia el servicio y comprueba que `GET /version` devuelva `v1.0.0`. La instancia tiene que estar corriendo y el secret `EC2_SSH_KEY` tiene que ser el `.pem` de ese apply.

## Observabilidad

| Métrica | Origen | Alarma |
| --- | --- | --- |
| `CPUUtilization` | EC2, nativa de AWS | Promedio mayor a 80% durante dos periodos de 5 minutos |
| `RDSErrors` | La API, con `put_metric_data` | 1 o más errores en 1 minuto |
| `TasksCreated` | La API, con `put_metric_data` | 50 o más tareas creadas en 5 minutos |

El dashboard se llama `todo-list-api`. La definición está en `alerting/cloudwatch-dashboard.json` y las alarmas en `alerting/alarms.json`.

Para disparar `RDSErrors`: detén la instancia RDS y llama a `GET /health` o `GET /tasks`. La alarma pasa a ALARM y, con el correo ya confirmado, llega el aviso.

`health-check` corre cada 5 minutos y también se puede lanzar a mano en Actions. Falla si `/health` no responde 200 o si el estado es `FAIL`. Con el lab apagado o las credenciales vencidas el job falla: es lo esperado.
